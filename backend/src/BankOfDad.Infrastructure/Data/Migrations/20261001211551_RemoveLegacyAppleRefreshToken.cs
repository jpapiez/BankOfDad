using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BankOfDad.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class RemoveLegacyAppleRefreshToken : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                """
                INSERT INTO "AppleRefreshTokens" ("Id", "UserId", "TokenEncrypted", "CreatedAt", "RevokedAt", "ReplacedByTokenId")
                SELECT
                    gen_random_uuid(),
                    u."Id",
                    u."AppleRefreshTokenEncrypted",
                    NOW(),
                    NULL,
                    (
                        SELECT t."Id"
                        FROM "AppleRefreshTokens" AS t
                        WHERE t."UserId" = u."Id"
                        ORDER BY t."CreatedAt", t."Id"
                        LIMIT 1
                    )
                FROM "Users" AS u
                WHERE u."AppleRefreshTokenEncrypted" IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM "AppleRefreshTokens" AS t
                      WHERE t."UserId" = u."Id"
                        AND t."TokenEncrypted" = u."AppleRefreshTokenEncrypted"
                  );
                """);

            migrationBuilder.DropIndex(
                name: "IX_AppleRefreshTokens_UserId",
                table: "AppleRefreshTokens");

            migrationBuilder.DropColumn(
                name: "AppleRefreshTokenEncrypted",
                table: "Users");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AppleRefreshTokenEncrypted",
                table: "Users",
                type: "character varying(2048)",
                maxLength: 2048,
                nullable: true);

            migrationBuilder.Sql(
                """
                UPDATE "Users" AS u
                SET "AppleRefreshTokenEncrypted" = (
                    SELECT t."TokenEncrypted"
                    FROM "AppleRefreshTokens" AS t
                    WHERE t."UserId" = u."Id"
                      AND t."RevokedAt" IS NULL
                    ORDER BY t."CreatedAt" DESC
                    LIMIT 1
                )
                WHERE EXISTS (
                    SELECT 1
                    FROM "AppleRefreshTokens" AS t
                    WHERE t."UserId" = u."Id"
                      AND t."RevokedAt" IS NULL
                );
                """);

            migrationBuilder.CreateIndex(
                name: "IX_AppleRefreshTokens_UserId",
                table: "AppleRefreshTokens",
                column: "UserId");
        }
    }
}
