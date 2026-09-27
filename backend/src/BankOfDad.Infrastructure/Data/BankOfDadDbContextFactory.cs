namespace BankOfDad.Infrastructure.Data;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

public sealed class BankOfDadDbContextFactory : IDesignTimeDbContextFactory<BankOfDadDbContext>
{
    public BankOfDadDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<BankOfDadDbContext>()
            .UseNpgsql("Host=localhost;Port=5432;Database=bankofdad;Username=bankofdad;Password=bankofdad-dev")
            .Options;
        return new BankOfDadDbContext(options);
    }
}
