using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BankOfDad.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddBills : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "BillId",
                table: "Notifications",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "Bills",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FamilyId = table.Column<Guid>(type: "uuid", nullable: false),
                    ChildId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedByParentId = table.Column<Guid>(type: "uuid", nullable: false),
                    Title = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", nullable: false),
                    Frequency = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    FirstDueDate = table.Column<DateOnly>(type: "date", nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    SendReminders = table.Column<bool>(type: "boolean", nullable: false),
                    SendReceipts = table.Column<bool>(type: "boolean", nullable: false),
                    LateFeeFlat = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    LateFeePercent = table.Column<decimal>(type: "numeric(9,6)", nullable: true),
                    LateFeeGraceDays = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    EndedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ConcurrencyToken = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Bills", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Bills_Families_FamilyId",
                        column: x => x.FamilyId,
                        principalTable: "Families",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_Bills_Users_ChildId",
                        column: x => x.ChildId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_Bills_Users_CreatedByParentId",
                        column: x => x.CreatedByParentId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BillCharges",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BillId = table.Column<Guid>(type: "uuid", nullable: false),
                    Seq = table.Column<int>(type: "integer", nullable: false),
                    DueDate = table.Column<DateOnly>(type: "date", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", nullable: false),
                    AmountPaid = table.Column<decimal>(type: "numeric(18,2)", nullable: false),
                    ReminderSentAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BillCharges", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BillCharges_Bills_BillId",
                        column: x => x.BillId,
                        principalTable: "Bills",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BillPayments",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BillId = table.Column<Guid>(type: "uuid", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", nullable: false),
                    PaidOn = table.Column<DateOnly>(type: "date", nullable: false),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    RecordedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ReceiptSentAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BillPayments", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BillPayments_Bills_BillId",
                        column: x => x.BillId,
                        principalTable: "Bills",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_BillPayments_Users_RecordedByUserId",
                        column: x => x.RecordedByUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BillLateFees",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BillId = table.Column<Guid>(type: "uuid", nullable: false),
                    ChargeId = table.Column<Guid>(type: "uuid", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", nullable: false),
                    AmountPaid = table.Column<decimal>(type: "numeric(18,2)", nullable: false),
                    AssessedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    WaivedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    WaivedByUserId = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BillLateFees", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BillLateFees_BillCharges_ChargeId",
                        column: x => x.ChargeId,
                        principalTable: "BillCharges",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_BillLateFees_Bills_BillId",
                        column: x => x.BillId,
                        principalTable: "Bills",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BillPaymentAllocations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PaymentId = table.Column<Guid>(type: "uuid", nullable: false),
                    Target = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ChargeId = table.Column<Guid>(type: "uuid", nullable: true),
                    LateFeeId = table.Column<Guid>(type: "uuid", nullable: true),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BillPaymentAllocations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BillPaymentAllocations_BillCharges_ChargeId",
                        column: x => x.ChargeId,
                        principalTable: "BillCharges",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_BillPaymentAllocations_BillLateFees_LateFeeId",
                        column: x => x.LateFeeId,
                        principalTable: "BillLateFees",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_BillPaymentAllocations_BillPayments_PaymentId",
                        column: x => x.PaymentId,
                        principalTable: "BillPayments",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BillCharges_BillId_DueDate",
                table: "BillCharges",
                columns: new[] { "BillId", "DueDate" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_BillCharges_BillId_Seq",
                table: "BillCharges",
                columns: new[] { "BillId", "Seq" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_BillLateFees_BillId_AssessedAt",
                table: "BillLateFees",
                columns: new[] { "BillId", "AssessedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_BillLateFees_ChargeId",
                table: "BillLateFees",
                column: "ChargeId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_BillPaymentAllocations_ChargeId",
                table: "BillPaymentAllocations",
                column: "ChargeId");

            migrationBuilder.CreateIndex(
                name: "IX_BillPaymentAllocations_LateFeeId",
                table: "BillPaymentAllocations",
                column: "LateFeeId");

            migrationBuilder.CreateIndex(
                name: "IX_BillPaymentAllocations_PaymentId",
                table: "BillPaymentAllocations",
                column: "PaymentId");

            migrationBuilder.CreateIndex(
                name: "IX_BillPayments_BillId_CreatedAt",
                table: "BillPayments",
                columns: new[] { "BillId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_BillPayments_RecordedByUserId",
                table: "BillPayments",
                column: "RecordedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Bills_ChildId",
                table: "Bills",
                column: "ChildId");

            migrationBuilder.CreateIndex(
                name: "IX_Bills_CreatedByParentId",
                table: "Bills",
                column: "CreatedByParentId");

            migrationBuilder.CreateIndex(
                name: "IX_Bills_FamilyId_Status",
                table: "Bills",
                columns: new[] { "FamilyId", "Status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BillPaymentAllocations");

            migrationBuilder.DropTable(
                name: "BillLateFees");

            migrationBuilder.DropTable(
                name: "BillPayments");

            migrationBuilder.DropTable(
                name: "BillCharges");

            migrationBuilder.DropTable(
                name: "Bills");

            migrationBuilder.DropColumn(
                name: "BillId",
                table: "Notifications");
        }
    }
}
