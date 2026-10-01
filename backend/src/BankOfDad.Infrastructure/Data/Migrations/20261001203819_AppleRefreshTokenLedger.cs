using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BankOfDad.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AppleRefreshTokenLedger : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "AppleDeletionStartedAt",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "AppleRefreshTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    TokenEncrypted = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    RevokedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReplacedByTokenId = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AppleRefreshTokens", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AppleRefreshTokens_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AppleRefreshTokens_UserId",
                table: "AppleRefreshTokens",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_AppleRefreshTokens_UserId_RevokedAt",
                table: "AppleRefreshTokens",
                columns: new[] { "UserId", "RevokedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AppleRefreshTokens");

            migrationBuilder.DropColumn(
                name: "AppleDeletionStartedAt",
                table: "Users");
        }
    }
}
