# The build stage always runs on the builder's native platform and cross-compiles for the
# target (docker buildx --platform linux/amd64,linux/arm64), so no QEMU emulation is needed.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
ARG NUGET_SOURCE=https://api.nuget.org/v3/index.json
WORKDIR /src
COPY . .
RUN dotnet restore src/BankOfDad.Api/BankOfDad.Api.csproj -a "$TARGETARCH" --source "$NUGET_SOURCE"
RUN dotnet publish src/BankOfDad.Api/BankOfDad.Api.csproj -c Release -a "$TARGETARCH" --self-contained false -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "BankOfDad.Api.dll"]
