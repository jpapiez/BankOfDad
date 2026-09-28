using System.Security.Claims;
using System.Data;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using BankOfDad.Api.Models;
using BankOfDad.Api.Services;
using BankOfDad.Domain;
using BankOfDad.Domain.Entities;
using BankOfDad.Domain.Services;
using BankOfDad.Infrastructure.Data;
using BankOfDad.Infrastructure.Push;
using BankOfDad.Infrastructure.Security;
using BankOfDad.Infrastructure.Time;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.WebUtilities;

var builder = WebApplication.CreateBuilder(args);
var env = builder.Environment;
var signingKey = builder.Configuration["Jwt:SigningKey"];
if (!env.IsDevelopment() && !env.IsEnvironment("Testing") && (string.IsNullOrWhiteSpace(signingKey) || signingKey.Length < 32))
{
    throw new InvalidOperationException("Jwt:SigningKey must be at least 32 characters outside Development/Testing.");
}
if (string.IsNullOrWhiteSpace(signingKey))
{
    signingKey = "testing-only-signing-key-change-me-0123456789";
}
if (string.IsNullOrWhiteSpace(builder.Configuration["Jwt:SigningKey"]))
{
    builder.Configuration["Jwt:SigningKey"] = signingKey;
}

builder.Services.Configure<JsonOptions>(options =>
{
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
});
builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();
builder.Services.AddDbContext<BankOfDadDbContext>(options => options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddScoped<ScheduleCalculator>();
builder.Services.AddScoped<LoanStateService>();
builder.Services.AddScoped<PaymentAllocator>();
builder.Services.AddScoped<TermsSummaryBuilder>();
builder.Services.AddSingleton<IClock, SystemClock>();
builder.Services.AddScoped<IPasswordService, PasswordService>();
builder.Services.AddScoped<IAppleTokenValidator, AppleTokenValidator>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<LoanSweeper>();
if (string.IsNullOrWhiteSpace(builder.Configuration["Apns:KeyId"]))
{
    builder.Services.AddScoped<IPushSender, LoggingPushSender>();
}
else
{
    builder.Services.AddHttpClient<IPushSender, ApnsPushSender>();
}
builder.Services.AddHostedService<DailySweepService>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.IncludeErrorDetails = env.IsDevelopment() || env.IsEnvironment("Testing");
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = "bankofdad",
        ValidAudience = "bankofdad",
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
        ClockSkew = TimeSpan.FromSeconds(30),
        RoleClaimType = "role",
        NameClaimType = "name"
    };
});
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Parent", policy => policy.RequireClaim("role", "parent"));
    options.AddPolicy("Child", policy => policy.RequireClaim("role", "child"));
});
if (!env.IsEnvironment("Testing"))
{
    builder.Services.AddRateLimiter(options => options.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions { PermitLimit = 100, Window = TimeSpan.FromMinutes(1), QueueLimit = 20 })));
}

var app = builder.Build();
app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var ex = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    var api = ex switch
    {
        ApiException apiException => apiException,
        BadHttpRequestException badRequest => new ApiException(badRequest.StatusCode, "Invalid request.", badRequest.Message),
        DbUpdateConcurrencyException => new ApiException(409, "The loan was changed by someone else. Please retry."),
        PostgresException { SqlState: PostgresErrorCodes.SerializationFailure } => new ApiException(409, "The loan was changed by someone else. Please retry."),
        _ => null
    };
    var status = api?.Status ?? StatusCodes.Status500InternalServerError;
    context.Response.StatusCode = status;
    var includeException = context.RequestServices.GetRequiredService<IHostEnvironment>().IsDevelopment() || context.RequestServices.GetRequiredService<IHostEnvironment>().IsEnvironment("Testing");
    await Results.Problem(title: api?.Title ?? "Unexpected error", detail: api?.Detail ?? (status == 500 && !includeException ? null : ex?.Message), statusCode: status).ExecuteAsync(context);
}));
app.UseStatusCodePages(async statusCodeContext =>
{
    var context = statusCodeContext.HttpContext;
    var status = context.Response.StatusCode;
    if (status is >= 400 and < 500)
    {
        await Results.Problem(title: ReasonPhrases.GetReasonPhrase(status), statusCode: status).ExecuteAsync(context);
    }
});
if (app.Environment.IsDevelopment()) app.MapOpenApi();
app.UseAuthentication();
app.UseAuthorization();
if (!env.IsEnvironment("Testing")) app.UseRateLimiter();

await ApplyMigrationsAsync(app.Services, app.Logger);

app.MapGet("/health", async (BankOfDadDbContext db, CancellationToken ct) => await db.Database.CanConnectAsync(ct) ? Results.Text("Healthy") : Results.Problem("Database unavailable", statusCode: 503));

var api = app.MapGroup("/api/v1");
var auth = api.MapGroup("/auth");
if (!env.IsEnvironment("Testing")) auth.RequireRateLimiting("auth");

auth.MapPost("/register", async (RegisterRequest request, BankOfDadDbContext db, AuthService authService, IClock clock, CancellationToken ct) =>
{
    ValidatePassword(request.Password);
    ValidateTimeZone(request.TimeZone);
    var email = NormalizeEmail(request.Email);
    if (await db.Users.AnyAsync(x => x.NormalizedEmail == email, ct)) throw new ApiException(409, "Email already registered.");
    var family = new Family { Name = Required(request.FamilyName, "familyName"), TimeZone = request.TimeZone, CreatedAt = clock.UtcNow };
    var user = new User { Family = family, Role = Role.Parent, DisplayName = Required(request.DisplayName, "displayName"), Email = request.Email, NormalizedEmail = email, CreatedAt = clock.UtcNow };
    user.PasswordHash = authService.HashPassword(user, request.Password);
    db.AddRange(family, user);
    await db.SaveChangesAsync(ct);
    return Results.Created("/api/v1/auth/me", await authService.IssueAsync(user, null, ct));
});

auth.MapPost("/login", async (LoginRequest request, BankOfDadDbContext db, AuthService authService, CancellationToken ct) =>
{
    var email = NormalizeEmail(request.Email);
    var user = await db.Users.SingleOrDefaultAsync(x => x.NormalizedEmail == email, ct);
    if (user is null || !authService.Verify(user, request.Password)) throw new ApiException(401, "Invalid email or password.");
    return Results.Ok(await authService.IssueAsync(user, null, ct));
});

auth.MapPost("/refresh", async (RefreshRequest request, AuthService authService, CancellationToken ct) => Results.Ok(await authService.RotateAsync(request.RefreshToken, ct)));
auth.MapPost("/logout", async (LogoutRequest request, AuthService authService, CancellationToken ct) => { await authService.LogoutAsync(request.RefreshToken, ct); return Results.NoContent(); });

auth.MapPost("/pair", async (PairRequest request, BankOfDadDbContext db, AuthService authService, IClock clock, CancellationToken ct) =>
{
    var hash = SecretHasher.Sha256(CodeGenerator.NormalizeCode(request.Code));
    var code = await db.PairingCodes.Include(x => x.ChildUser).SingleOrDefaultAsync(x => x.CodeHash == hash, ct);
    if (code?.ChildUser is null || code.UsedAt is not null || code.ExpiresAt <= clock.UtcNow) throw new ApiException(401, "Invalid pairing code.");
    code.UsedAt = clock.UtcNow;
    await db.SaveChangesAsync(ct);
    return Results.Ok(await authService.IssueAsync(code.ChildUser, request.DeviceName, ct));
});

auth.MapPost("/accept-invite", async (AcceptInviteRequest request, BankOfDadDbContext db, AuthService authService, IClock clock, CancellationToken ct) =>
{
    ValidatePassword(request.Password);
    var email = NormalizeEmail(request.Email);
    if (await db.Users.AnyAsync(x => x.NormalizedEmail == email, ct)) throw new ApiException(409, "Email already registered.");
    var invite = await db.FamilyInvites.SingleOrDefaultAsync(x => x.CodeHash == SecretHasher.Sha256(CodeGenerator.NormalizeCode(request.InviteCode)), ct);
    if (invite is null || invite.UsedAt is not null || invite.ExpiresAt <= clock.UtcNow) throw new ApiException(401, "Invalid invite code.");
    var user = new User { FamilyId = invite.FamilyId, Role = Role.Parent, DisplayName = Required(request.DisplayName, "displayName"), Email = request.Email, NormalizedEmail = email, CreatedAt = clock.UtcNow };
    user.PasswordHash = authService.HashPassword(user, request.Password);
    invite.UsedAt = clock.UtcNow;
    db.Users.Add(user);
    await db.SaveChangesAsync(ct);
    return Results.Created("/api/v1/auth/me", await authService.IssueAsync(user, null, ct));
});

auth.MapPost("/apple", async (AppleRequest request, BankOfDadDbContext db, AuthService authService, IAppleTokenValidator apple, IClock clock, CancellationToken ct) =>
{
    var appleUser = await apple.ValidateAsync(request.IdentityToken, ct);
    var existing = await db.Users.SingleOrDefaultAsync(x => x.AppleSubject == appleUser.Subject, ct);
    if (existing is not null) return Results.Ok(await authService.IssueAsync(existing, null, ct));
    if (appleUser.Email is not null)
    {
        // Apple only issues verified emails, so link to an existing email/password parent account.
        var normalized = NormalizeEmail(appleUser.Email);
        var byEmail = await db.Users.SingleOrDefaultAsync(x => x.NormalizedEmail == normalized, ct);
        if (byEmail is not null)
        {
            if (byEmail.AppleSubject is not null) throw new ApiException(409, "This email is linked to a different Apple ID.");
            byEmail.AppleSubject = appleUser.Subject;
            await db.SaveChangesAsync(ct);
            return Results.Ok(await authService.IssueAsync(byEmail, null, ct));
        }
    }
    Guid familyId;
    if (!string.IsNullOrWhiteSpace(request.InviteCode))
    {
        var invite = await db.FamilyInvites.SingleOrDefaultAsync(x => x.CodeHash == SecretHasher.Sha256(CodeGenerator.NormalizeCode(request.InviteCode)), ct);
        if (invite is null || invite.UsedAt is not null || invite.ExpiresAt <= clock.UtcNow) throw new ApiException(401, "Invalid invite code.");
        invite.UsedAt = clock.UtcNow;
        familyId = invite.FamilyId;
    }
    else
    {
        var tz = request.TimeZone ?? "America/Los_Angeles";
        ValidateTimeZone(tz);
        var family = new Family { Name = request.FamilyName ?? "Family", TimeZone = tz, CreatedAt = clock.UtcNow };
        db.Families.Add(family);
        familyId = family.Id;
    }
    var user = new User { FamilyId = familyId, Role = Role.Parent, DisplayName = request.DisplayName ?? appleUser.Email ?? "Parent", Email = appleUser.Email, NormalizedEmail = appleUser.Email is null ? null : NormalizeEmail(appleUser.Email), AppleSubject = appleUser.Subject, CreatedAt = clock.UtcNow };
    db.Users.Add(user);
    await db.SaveChangesAsync(ct);
    return Results.Created("/api/v1/auth/me", await authService.IssueAsync(user, null, ct));
});

auth.MapGet("/me", async (ClaimsPrincipal user, BankOfDadDbContext db, CancellationToken ct) =>
{
    var current = await db.Users.FindAsync([user.UserId()], ct);
    return current is null ? Results.NotFound() : Results.Ok(DtoMapper.User(current));
}).RequireAuthorization();

var familyGroup = api.MapGroup("/family").RequireAuthorization("Parent");
familyGroup.MapGet("/", async (ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) => Results.Ok(await GetFamilyDto(user.FamilyId(), db, clock, ct)));
familyGroup.MapPatch("/", async (FamilyPatchRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var family = await db.Families.Include(x => x.Users).SingleAsync(x => x.Id == user.FamilyId(), ct);
    if (!string.IsNullOrWhiteSpace(request.Name)) family.Name = request.Name;
    if (!string.IsNullOrWhiteSpace(request.TimeZone)) { ValidateTimeZone(request.TimeZone); family.TimeZone = request.TimeZone; }
    await db.SaveChangesAsync(ct);
    return Results.Ok(await GetFamilyDto(family.Id, db, clock, ct));
});
familyGroup.MapPost("/invites", async (InviteRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var code = CodeGenerator.Generate(10);
    var invite = new FamilyInvite { FamilyId = user.FamilyId(), CreatedByUserId = user.UserId(), CodeHash = SecretHasher.Sha256(code), Email = request.Email, ExpiresAt = clock.UtcNow.AddDays(7) };
    db.FamilyInvites.Add(invite);
    await db.SaveChangesAsync(ct);
    return Results.Created("/api/v1/family/invites", new InviteResponse(code, invite.ExpiresAt));
});
familyGroup.MapPost("/children", async (ChildRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var child = new User { FamilyId = user.FamilyId(), Role = Role.Child, DisplayName = Required(request.DisplayName, "displayName"), AvatarColor = request.AvatarColor, CreatedAt = clock.UtcNow };
    db.Users.Add(child);
    await db.SaveChangesAsync(ct);
    return Results.Created($"/api/v1/family/children/{child.Id}", DtoMapper.Child(child));
});
familyGroup.MapPatch("/children/{childId:guid}", async (Guid childId, ChildPatchRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var child = await db.Users.SingleOrDefaultAsync(x => x.Id == childId && x.FamilyId == user.FamilyId() && x.Role == Role.Child, ct) ?? throw new ApiException(404, "Child not found.");
    if (!string.IsNullOrWhiteSpace(request.DisplayName)) child.DisplayName = request.DisplayName;
    if (request.AvatarColor is not null) child.AvatarColor = request.AvatarColor;
    await db.SaveChangesAsync(ct);
    return Results.Ok(DtoMapper.Child(child, await CountPairedDevices(db, child.Id, clock, ct)));
});
familyGroup.MapPost("/children/{childId:guid}/pairing-code", async (Guid childId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    _ = await db.Users.SingleOrDefaultAsync(x => x.Id == childId && x.FamilyId == user.FamilyId() && x.Role == Role.Child, ct) ?? throw new ApiException(404, "Child not found.");
    var code = CodeGenerator.Generate();
    var pairing = new PairingCode { ChildUserId = childId, CodeHash = SecretHasher.Sha256(code), ExpiresAt = clock.UtcNow.AddMinutes(15) };
    db.PairingCodes.Add(pairing);
    await db.SaveChangesAsync(ct);
    var display = CodeGenerator.FormatPairingCode(code);
    return Results.Created("/api/v1/family/children/pairing-code", new PairingCodeResponse(display, $"bankofdad://pair?code={code}", pairing.ExpiresAt));
});
familyGroup.MapDelete("/children/{childId:guid}/devices", async (Guid childId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    _ = await db.Users.SingleOrDefaultAsync(x => x.Id == childId && x.FamilyId == user.FamilyId() && x.Role == Role.Child, ct) ?? throw new ApiException(404, "Child not found.");
    await db.RefreshTokens.Where(x => x.UserId == childId && x.RevokedAt == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, clock.UtcNow), ct);
    await db.DeviceTokens.Where(x => x.UserId == childId).ExecuteDeleteAsync(ct);
    return Results.NoContent();
});

var loans = api.MapGroup("/loans").RequireAuthorization("Parent");
loans.MapPost("/preview", async (LoanTermsInput input, ClaimsPrincipal user, BankOfDadDbContext db, ScheduleCalculator calc, IClock clock, CancellationToken ct) =>
{
    await ValidateLoanTerms(input, user.FamilyId(), db, clock, ct);
    return Results.Ok(DtoMapper.Preview(calc.Calculate(ToTerms(input))));
});
loans.MapPost("/", async (LoanTermsInput input, ClaimsPrincipal user, BankOfDadDbContext db, ScheduleCalculator calc, NotificationService notifications, IClock clock, CancellationToken ct) =>
{
    await ValidateLoanTerms(input, user.FamilyId(), db, clock, ct);
    var schedule = calc.Calculate(ToTerms(input));
    var loan = new Loan { FamilyId = user.FamilyId(), BorrowerChildId = input.ChildId, CreatedByParentId = user.UserId(), Title = input.Title.Trim(), Principal = input.Principal, InterestEnabled = input.InterestEnabled, AnnualRate = input.InterestEnabled ? input.AnnualRate : 0m, Frequency = input.Frequency, InstallmentCount = input.InstallmentCount, FirstDueDate = input.FirstDueDate, InstallmentAmount = schedule.InstallmentAmount, SendReminders = input.SendReminders, SendReceipts = input.SendReceipts, LateFeeFlat = input.LateFeeFlat, LateFeePercent = input.LateFeePercent, LateFeeGraceDays = input.LateFeeGraceDays, CreatedAt = clock.UtcNow };
    loan.Installments = schedule.Installments.Select(x => new Installment { LoanId = loan.Id, Seq = x.Seq, DueDate = x.DueDate, PrincipalDue = x.PrincipalDue, InterestDue = x.InterestDue }).ToList();
    db.Loans.Add(loan);
    await db.SaveChangesAsync(ct);
    await notifications.CreateAndPushAsync(loan.BorrowerChildId, NotificationType.LoanCreated, "New loan", $"A new loan \"{loan.Title}\" was created for {Money.Format(loan.Principal)}.", loan.Id, ct);
    loan = await LoadLoan(db, loan.Id, user.FamilyId(), ct) ?? loan;
    return Results.Created($"/api/v1/loans/{loan.Id}", DtoMapper.LoanDetail(loan, TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock)));
});
loans.MapGet("/", async (LoanStatus? status, Guid? childId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var tz = await GetFamilyTimeZone(user.FamilyId(), db, ct);
    var query = db.Loans.IncludeAll().Where(x => x.FamilyId == user.FamilyId());
    if (status is not null) query = query.Where(x => x.Status == status);
    if (childId is not null) query = query.Where(x => x.BorrowerChildId == childId);
    var list = await query.ToListAsync(ct);
    return Results.Ok(list.Select(x => DtoMapper.LoanSummary(x, TodayFor(tz, clock))).ToList());
});
loans.MapGet("/{loanId:guid}", async (Guid loanId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) => Results.Ok(DtoMapper.LoanDetail(await RequireLoan(db, loanId, user.FamilyId(), ct), TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock))));
loans.MapPatch("/{loanId:guid}", async (Guid loanId, LoanPatchRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var loan = await RequireLoan(db, loanId, user.FamilyId(), ct);
    if (!string.IsNullOrWhiteSpace(request.Title)) loan.Title = Required(request.Title, "title");
    if (request.SendReminders is not null) loan.SendReminders = request.SendReminders.Value;
    if (request.SendReceipts is not null) loan.SendReceipts = request.SendReceipts.Value;
    await db.SaveChangesAsync(ct);
    return Results.Ok(DtoMapper.LoanDetail(loan, TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock)));
});
loans.MapPatch("/{loanId:guid}/installments/{installmentId:guid}", async (Guid loanId, Guid installmentId, InstallmentPatchRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var loan = await RequireLoan(db, loanId, user.FamilyId(), ct);
    if (loan.Status != LoanStatus.Active) throw new ApiException(409, "Loan is not active.");
    var installment = loan.Installments.SingleOrDefault(x => x.Id == installmentId) ?? throw new ApiException(404, "Installment not found.");
    var state = new LoanStateService();
    if (state.InstallmentRemaining(installment) <= 0m) throw new ApiException(409, "Paid installments cannot be changed.");
    var previous = loan.Installments.Where(x => x.Seq < installment.Seq).OrderByDescending(x => x.Seq).FirstOrDefault();
    var next = loan.Installments.Where(x => x.Seq > installment.Seq).OrderBy(x => x.Seq).FirstOrDefault();
    if ((previous is not null && request.DueDate <= previous.DueDate) || (next is not null && request.DueDate >= next.DueDate)) throw new ApiException(400, "Due date must stay between adjacent installments.");
    installment.DueDate = request.DueDate;
    installment.ReminderSentAt = null;
    await db.SaveChangesAsync(ct);
    return Results.Ok(DtoMapper.LoanDetail(loan, TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock)));
});
loans.MapPost("/{loanId:guid}/cancel", async (Guid loanId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var loan = await RequireLoan(db, loanId, user.FamilyId(), ct);
    if (loan.Status != LoanStatus.Active) throw new ApiException(409, "Loan is not active.");
    loan.Status = LoanStatus.Cancelled;
    loan.CancelledAt = clock.UtcNow;
    await db.SaveChangesAsync(ct);
    return Results.Ok(DtoMapper.LoanDetail(loan, TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock)));
});
loans.MapPost("/{loanId:guid}/payments", async (Guid loanId, PaymentRequest request, ClaimsPrincipal user, BankOfDadDbContext db, PaymentAllocator allocator, LoanStateService state, NotificationService notifications, IClock clock, CancellationToken ct) =>
{
    if (request.Amount <= 0m) throw new ApiException(400, "Payment amount must be greater than zero.");
    await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
    var loan = await RequireLoan(db, loanId, user.FamilyId(), ct);
    if (loan.Status != LoanStatus.Active) throw new ApiException(409, "Loan is not active.");
    var payment = new Payment { LoanId = loan.Id, Amount = Money.Round(request.Amount), PaidOn = request.PaidOn, Note = request.Note, RecordedByUserId = user.UserId(), CreatedAt = clock.UtcNow };
    try
    {
        var drafts = allocator.Allocate(loan, payment.Amount);
        payment.Allocations = drafts.Select(x => new PaymentAllocation { PaymentId = payment.Id, Target = x.Target, InstallmentId = x.InstallmentId, LateFeeId = x.LateFeeId, Amount = x.Amount }).ToList();
    }
    catch (InvalidOperationException ex) { throw new ApiException(409, ex.Message); }
    db.Payments.Add(payment);
    loan.ConcurrencyToken = Guid.NewGuid();
    if (state.IsPaidOff(loan)) { loan.Status = LoanStatus.PaidOff; loan.PaidOffAt = clock.UtcNow; }
    await db.SaveChangesAsync(ct);
    if (loan.SendReceipts)
    {
        var remaining = state.Balance(loan);
        payment.ReceiptSentAt = clock.UtcNow;
        await notifications.CreateAndPushAsync(loan.BorrowerChildId, NotificationType.Receipt, "Payment received", $"We received your {Money.Format(payment.Amount)} payment for \"{loan.Title}\". Remaining balance: {Money.Format(remaining)}.", loan.Id, ct);
    }
    payment = await db.Payments.Include(x => x.RecordedByUser).Include(x => x.Allocations).ThenInclude(x => x.Installment).SingleAsync(x => x.Id == payment.Id, ct);
    await transaction.CommitAsync(ct);
    return Results.Created($"/api/v1/loans/{loanId}/payments/{payment.Id}", DtoMapper.Payment(payment));
});
loans.MapGet("/{loanId:guid}/payments", async (Guid loanId, ClaimsPrincipal user, BankOfDadDbContext db, CancellationToken ct) =>
{
    _ = await RequireLoan(db, loanId, user.FamilyId(), ct);
    var payments = await db.Payments.Include(x => x.RecordedByUser).Include(x => x.Allocations).ThenInclude(x => x.Installment).Where(x => x.LoanId == loanId).OrderByDescending(x => x.CreatedAt).ToListAsync(ct);
    return Results.Ok(payments.Select(DtoMapper.Payment).ToList());
});
loans.MapPost("/{loanId:guid}/late-fees/{lateFeeId:guid}/waive", async (Guid loanId, Guid lateFeeId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var loan = await RequireLoan(db, loanId, user.FamilyId(), ct);
    var fee = loan.LateFees.SingleOrDefault(x => x.Id == lateFeeId) ?? throw new ApiException(404, "Late fee not found.");
    fee.WaivedAt = clock.UtcNow;
    fee.WaivedByUserId = user.UserId();
    if (new LoanStateService().IsPaidOff(loan)) { loan.Status = LoanStatus.PaidOff; loan.PaidOffAt = clock.UtcNow; }
    await db.SaveChangesAsync(ct);
    return Results.Ok(DtoMapper.LoanDetail(loan, TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock)));
});

api.MapGet("/dashboard", async (ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var tz = await GetFamilyTimeZone(user.FamilyId(), db, ct);
    var today = TodayFor(tz, clock);
    var loansList = await db.Loans.IncludeAll().Where(x => x.FamilyId == user.FamilyId() && x.Status == LoanStatus.Active).ToListAsync(ct);
    var state = new LoanStateService();
    var upcoming = loansList.SelectMany(l => l.Installments.Where(i => state.InstallmentRemaining(i) > 0m && i.DueDate <= today.AddDays(30)).Select(i => new UpcomingDto(l.Id, l.Title, l.BorrowerChild?.DisplayName ?? string.Empty, i.DueDate, state.InstallmentRemaining(i)))).OrderBy(x => x.DueDate).ToList();
    return Results.Ok(new DashboardDto(loansList.Sum(state.Balance), loansList.Count, loansList.Sum(l => l.Installments.Count(i => state.Status(i, today, l.LateFeeGraceDays) == InstallmentStatus.Late)), upcoming));
}).RequireAuthorization("Parent");

var childGroup = api.MapGroup("/me").RequireAuthorization("Child");
childGroup.MapGet("/loans", async (ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var tz = await GetFamilyTimeZone(user.FamilyId(), db, ct);
    var list = await db.Loans.IncludeAll().Where(x => x.FamilyId == user.FamilyId() && x.BorrowerChildId == user.UserId()).ToListAsync(ct);
    return Results.Ok(list.Select(x => DtoMapper.LoanSummary(x, TodayFor(tz, clock))).ToList());
});
childGroup.MapGet("/loans/{loanId:guid}", async (Guid loanId, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var loan = await LoadLoan(db, loanId, user.FamilyId(), ct);
    if (loan is null || loan.BorrowerChildId != user.UserId()) throw new ApiException(404, "Loan not found.");
    return Results.Ok(DtoMapper.LoanDetail(loan, TodayFor(await GetFamilyTimeZone(user.FamilyId(), db, ct), clock)));
});

api.MapGet("/notifications", async (bool? unreadOnly, ClaimsPrincipal user, BankOfDadDbContext db, CancellationToken ct) =>
{
    var items = await db.Notifications.Where(x => x.UserId == user.UserId() && (unreadOnly != true || x.ReadAt == null)).OrderByDescending(x => x.CreatedAt).ToListAsync(ct);
    return Results.Ok(items.Select(DtoMapper.Notification).ToList());
}).RequireAuthorization();
api.MapPost("/notifications/{id:guid}/read", async (Guid id, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    var notification = await db.Notifications.SingleOrDefaultAsync(x => x.Id == id && x.UserId == user.UserId(), ct) ?? throw new ApiException(404, "Notification not found.");
    notification.ReadAt = clock.UtcNow;
    await db.SaveChangesAsync(ct);
    return Results.NoContent();
}).RequireAuthorization();
api.MapPost("/notifications/read-all", async (ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    await db.Notifications.Where(x => x.UserId == user.UserId() && x.ReadAt == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.ReadAt, clock.UtcNow), ct);
    return Results.NoContent();
}).RequireAuthorization();
api.MapPost("/devices", async (DeviceRequest request, ClaimsPrincipal user, BankOfDadDbContext db, IClock clock, CancellationToken ct) =>
{
    if (request.Environment is not ("sandbox" or "production")) throw new ApiException(400, "Invalid device environment.");
    var token = await db.DeviceTokens.SingleOrDefaultAsync(x => x.ApnsToken == request.ApnsToken, ct);
    if (token is null) db.DeviceTokens.Add(new DeviceToken { UserId = user.UserId(), ApnsToken = request.ApnsToken, Environment = request.Environment, UpdatedAt = clock.UtcNow });
    else { token.UserId = user.UserId(); token.Environment = request.Environment; token.UpdatedAt = clock.UtcNow; }
    await db.SaveChangesAsync(ct);
    return Results.NoContent();
}).RequireAuthorization();
api.MapDelete("/devices/{apnsToken}", async (string apnsToken, ClaimsPrincipal user, BankOfDadDbContext db, CancellationToken ct) =>
{
    await db.DeviceTokens.Where(x => x.UserId == user.UserId() && x.ApnsToken == apnsToken).ExecuteDeleteAsync(ct);
    return Results.NoContent();
}).RequireAuthorization();

await app.RunAsync();

static async Task ApplyMigrationsAsync(IServiceProvider services, ILogger logger)
{
    using var scope = services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<BankOfDadDbContext>();
    for (var attempt = 1; attempt <= 10; attempt++)
    {
        try { await db.Database.MigrateAsync(); return; }
        catch (NpgsqlException) when (attempt < 10) { logger.LogInformation("Database unavailable; retrying migration attempt {Attempt}.", attempt); await Task.Delay(TimeSpan.FromSeconds(3)); }
        catch (SocketException) when (attempt < 10) { logger.LogInformation("Database unavailable; retrying migration attempt {Attempt}.", attempt); await Task.Delay(TimeSpan.FromSeconds(3)); }
    }
}

static string Required(string? value, string name)
{
    if (string.IsNullOrWhiteSpace(value)) throw new ApiException(400, $"{name} is required.");
    return value.Trim();
}

static string NormalizeEmail(string? email)
{
    if (string.IsNullOrWhiteSpace(email) || !email.Contains('@')) throw new ApiException(400, "Valid email is required.");
    return email.Trim().ToLowerInvariant();
}

static void ValidatePassword(string? password)
{
    if (string.IsNullOrWhiteSpace(password) || password.Length < 8) throw new ApiException(400, "Password must be at least 8 characters.");
}

static void ValidateTimeZone(string? timeZone)
{
    if (string.IsNullOrWhiteSpace(timeZone)) throw new ApiException(400, "Invalid time zone.");
    try { _ = TimeZoneInfo.FindSystemTimeZoneById(timeZone); }
    catch (TimeZoneNotFoundException) { throw new ApiException(400, "Invalid time zone."); }
    catch (InvalidTimeZoneException) { throw new ApiException(400, "Invalid time zone."); }
}

static async Task ValidateLoanTerms(LoanTermsInput input, Guid familyId, BankOfDadDbContext db, IClock clock, CancellationToken ct)
{
    if (input.Principal is < 0.01m or > 1_000_000m) throw new ApiException(400, "Principal is out of range.");
    if (input.InstallmentCount is < 1 or > 520) throw new ApiException(400, "Installment count is out of range.");
    if (input.AnnualRate is < 0m or > 1m) throw new ApiException(400, "Annual rate is out of range.");
    if ((input.LateFeeFlat ?? 0m) < 0m) throw new ApiException(400, "Late fee flat must be non-negative.");
    if ((input.LateFeePercent ?? 0m) is < 0m or > 1m) throw new ApiException(400, "Late fee percent is out of range.");
    if (input.LateFeeGraceDays is < 0 or > 60) throw new ApiException(400, "Late fee grace days is out of range.");
    if (Required(input.Title, "title").Length > 100) throw new ApiException(400, "Title is too long.");
    var family = await db.Families.FindAsync([familyId], ct) ?? throw new ApiException(404, "Family not found.");
    if (input.FirstDueDate < TodayFor(family.TimeZone, clock)) throw new ApiException(400, "First due date cannot be in the past.");
    if (!await db.Users.AnyAsync(x => x.Id == input.ChildId && x.FamilyId == familyId && x.Role == Role.Child, ct)) throw new ApiException(404, "Child not found.");
}

static LoanTerms ToTerms(LoanTermsInput input) => new(input.ChildId, input.Title, input.Principal, input.InterestEnabled, input.InterestEnabled ? input.AnnualRate : 0m, input.Frequency, input.InstallmentCount, input.FirstDueDate, input.LateFeeFlat, input.LateFeePercent, input.LateFeeGraceDays, input.SendReminders, input.SendReceipts);

static DateOnly TodayFor(string timeZone, IClock clock)
{
    var tz = TimeZoneInfo.FindSystemTimeZoneById(timeZone);
    return DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(clock.UtcNow, tz).DateTime);
}

static async Task<string> GetFamilyTimeZone(Guid familyId, BankOfDadDbContext db, CancellationToken ct) => (await db.Families.FindAsync([familyId], ct) ?? throw new ApiException(404, "Family not found.")).TimeZone;

static async Task<FamilyDto> GetFamilyDto(Guid familyId, BankOfDadDbContext db, IClock clock, CancellationToken ct)
{
    var family = await db.Families.Include(x => x.Users).SingleAsync(x => x.Id == familyId, ct);
    var childIds = family.Users.Where(x => x.Role == Role.Child).Select(x => x.Id).ToList();
    var now = clock.UtcNow;
    var devices = await db.RefreshTokens.Where(x => childIds.Contains(x.UserId) && x.RevokedAt == null && x.ExpiresAt > now).GroupBy(x => x.UserId).Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
    return DtoMapper.Family(family, devices);
}

static Task<int> CountPairedDevices(BankOfDadDbContext db, Guid childId, IClock clock, CancellationToken ct)
{
    var now = clock.UtcNow;
    return db.RefreshTokens.CountAsync(x => x.UserId == childId && x.RevokedAt == null && x.ExpiresAt > now, ct);
}

static Task<Loan?> LoadLoan(BankOfDadDbContext db, Guid loanId, Guid familyId, CancellationToken ct) => db.Loans.IncludeAll().SingleOrDefaultAsync(x => x.Id == loanId && x.FamilyId == familyId, ct);
static async Task<Loan> RequireLoan(BankOfDadDbContext db, Guid loanId, Guid familyId, CancellationToken ct) => await LoadLoan(db, loanId, familyId, ct) ?? throw new ApiException(404, "Loan not found.");

public partial class Program;
