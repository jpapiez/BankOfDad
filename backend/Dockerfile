# The build stage always runs on the builder's native platform and cross-compiles for the
# target (docker buildx --platform linux/amd64,linux/arm64), so no QEMU emulation is needed.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
# The v2 endpoint avoids intermittent TLS EOFs seen by the SDK image when it
# negotiates with api.nuget.org's v3 service index. Keep this overrideable for
# air-gapped or enterprise feeds. Retries handle transient DNS/TLS resets in
# container build networks without requiring a manual rebuild.
ARG NUGET_SOURCE=https://www.nuget.org/api/v2
WORKDIR /src
COPY . .
RUN for attempt in 1 2 3 4 5; do \
      dotnet restore src/BankOfDad.Api/BankOfDad.Api.csproj -a "$TARGETARCH" --source "$NUGET_SOURCE" --disable-parallel && exit 0; \
      echo "NuGet restore attempt $attempt failed; retrying..." >&2; \
      sleep $((attempt * 5)); \
    done; \
    exit 1
RUN dotnet publish src/BankOfDad.Api/BankOfDad.Api.csproj -c Release -a "$TARGETARCH" --self-contained false -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "BankOfDad.Api.dll"]
