# syntax=docker/dockerfile:1.2

FROM ghcr.io/github/gh-base-image/go-builder-focal:20250725-230825-g446ca4a55 AS build

COPY . /app
WORKDIR /app
RUN make build

# Build the production container
FROM ghcr.io/github/gh-base-image/gh-base-focal:20250711-165924-g6f92253c7 AS run

COPY --chown=github:github --from=build /app/bin/ /app/bin/
COPY --from=build /app/config/db.yaml /app/config/db.yaml
WORKDIR /app
EXPOSE 8080
USER github
CMD ["./bin/server"]
