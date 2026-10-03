using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BankOfDad.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSelfHostedOnboarding : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ChildCredentialKind",
                table: "Users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NormalizedUsername",
                table: "Users",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Username",
                table: "Users",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "EnrollmentTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    TokenHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    FamilyId = table.Column<Guid>(type: "uuid", nullable: true),
                    ChildUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    Email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: true),
                    CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UsedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnrollmentTokens", x => x.Id);
                    table.ForeignKey(
                        name: "FK_EnrollmentTokens_Families_FamilyId",
                        column: x => x.FamilyId,
                        principalTable: "Families",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnrollmentTokens_Users_ChildUserId",
                        column: x => x.ChildUserId,
                        principalTable: "Users",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "ServerInstallations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FamilyId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    InitializedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ServerInstallations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ServerInstallations_Families_FamilyId",
                        column: x => x.FamilyId,
                        principalTable: "Families",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateIndex(
                name: "IX_Users_NormalizedUsername",
                table: "Users",
                column: "NormalizedUsername",
                unique: true,
                filter: "\"NormalizedUsername\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_EnrollmentTokens_ChildUserId",
                table: "EnrollmentTokens",
                column: "ChildUserId");

            migrationBuilder.CreateIndex(
                name: "IX_EnrollmentTokens_FamilyId_Kind_ExpiresAt",
                table: "EnrollmentTokens",
                columns: new[] { "FamilyId", "Kind", "ExpiresAt" });

            migrationBuilder.CreateIndex(
                name: "IX_EnrollmentTokens_TokenHash",
                table: "EnrollmentTokens",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ServerInstallations_FamilyId",
                table: "ServerInstallations",
                column: "FamilyId",
                unique: true,
                filter: "\"FamilyId\" IS NOT NULL");

            migrationBuilder.Sql(
                """
                DO $$
                DECLARE
                    family_count integer;
                    existing_family_id uuid;
                    existing_created_at timestamp with time zone;
                BEGIN
                    SELECT COUNT(*) INTO family_count FROM "Families";

                    IF family_count = 1 THEN
                        SELECT "Id", "CreatedAt" INTO existing_family_id, existing_created_at
                        FROM "Families"
                        LIMIT 1;

                        INSERT INTO "ServerInstallations" ("Id", "FamilyId", "CreatedAt", "InitializedAt")
                        VALUES (gen_random_uuid(), existing_family_id, existing_created_at, NOW());
                    ELSE
                        -- Existing pre-self-hosted databases may contain multiple
                        -- families. Keep those families intact and let startup
                        -- expose the legacy multi-family mode instead of making a
                        -- universal schema migration fail.
                        INSERT INTO "ServerInstallations" ("Id", "FamilyId", "CreatedAt", "InitializedAt")
                        VALUES (gen_random_uuid(), NULL, NOW(), NULL);
                    END IF;
                END $$;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EnrollmentTokens");

            migrationBuilder.DropTable(
                name: "ServerInstallations");

            migrationBuilder.DropIndex(
                name: "IX_Users_NormalizedUsername",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "ChildCredentialKind",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "NormalizedUsername",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "Username",
                table: "Users");
        }
    }
}
