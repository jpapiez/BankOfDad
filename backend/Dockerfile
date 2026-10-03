# The build stage always runs on the builder's native platform and cross-compiles for the
# target (docker buildx --platform linux/amd64,linux/arm64), so no QEMU emulation is needed.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
# Keep the standard NuGet v3 service index as the default. Retries handle
# transient DNS/TLS resets in container build networks; the v2 endpoint is a
# built-in transport fallback for environments that cannot reach api.nuget.org.
ARG NUGET_SOURCE=https://api.nuget.org/v3/index.json
WORKDIR /src
COPY . .
RUN for attempt in 1 2 3 4 5; do \
      dotnet restore src/BankOfDad.Api/BankOfDad.Api.csproj -a "$TARGETARCH" --source "$NUGET_SOURCE" --disable-parallel && exit 0; \
      echo "NuGet restore attempt $attempt failed; retrying..." >&2; \
      sleep $((attempt * 5)); \
    done; \
    if [ "$NUGET_SOURCE" = "https://api.nuget.org/v3/index.json" ]; then \
      echo "NuGet v3 unavailable; retrying with the compatible NuGet v2 transport endpoint." >&2; \
      for attempt in 1 2 3 4 5; do \
        dotnet restore src/BankOfDad.Api/BankOfDad.Api.csproj -a "$TARGETARCH" --source "$NUGET_SOURCE" --source "https://www.nuget.org/api/v2" --ignore-failed-sources --disable-parallel && exit 0; \
        echo "NuGet v2 fallback attempt $attempt failed; retrying..." >&2; \
        sleep $((attempt * 5)); \
      done; \
    fi; \
    exit 1
RUN dotnet publish src/BankOfDad.Api/BankOfDad.Api.csproj -c Release -a "$TARGETARCH" --self-contained false -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "BankOfDad.Api.dll"]
