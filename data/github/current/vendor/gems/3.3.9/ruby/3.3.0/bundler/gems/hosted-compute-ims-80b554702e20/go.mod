module github.com/github/hosted-compute-ims

go 1.23.3

require (
	buf.build/gen/go/bufbuild/protovalidate/protocolbuffers/go v1.35.2-20240920164238-5a7b106cbb87.1
	entgo.io/ent v0.14.1
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.16.0
	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.8.0
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5 v5.7.0
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources v1.2.0
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage v1.6.0
	github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v1.5.0
	github.com/DATA-DOG/go-sqlmock v1.5.2
	github.com/Masterminds/semver v1.5.0
	github.com/bufbuild/protovalidate-go v0.7.2
	github.com/coreos/go-oidc/v3 v3.11.0
	github.com/github/aqueduct-client-go/v2 v2.5.10
	github.com/github/github-telemetry-go v1.32.1
	github.com/github/go-auth v0.7.2
	github.com/github/go-config v1.7.2
	github.com/github/go-exceptions v1.1.0
	github.com/github/go-http v0.2.3
	github.com/github/go-stats v1.18.1
	github.com/github/go-twirp v1.0.1
	github.com/github/go-twirp/v2 v2.3.5
	github.com/github/hosted-compute-core/cryptography v0.0.0-20241118153748-478790fb1549
	github.com/github/hosted-compute-core/oidc v0.0.0-20241118153748-478790fb1549
	github.com/github/hosted-compute-core/telemetry v0.0.0-20241118153748-478790fb1549
	github.com/github/monolith-twirp-features v1.6.0
	github.com/go-sql-driver/mysql v1.8.1
	github.com/golang-jwt/jwt v3.2.2+incompatible
	github.com/golang-jwt/jwt/v4 v4.5.1
	github.com/google/uuid v1.6.0
	github.com/jmoiron/sqlx v1.4.0
	github.com/patrickmn/go-cache v2.1.0+incompatible
	github.com/pkg/errors v0.9.1
	github.com/stretchr/testify v1.9.0
	github.com/twitchtv/twirp v8.1.3+incompatible
	github.com/ugorji/go/codec v1.2.12
	go.opentelemetry.io/otel v1.32.0
	go.opentelemetry.io/otel/trace v1.32.0
	go.uber.org/mock v0.5.0
	go.uber.org/zap v1.27.0
	google.golang.org/protobuf v1.35.2
	gopkg.in/yaml.v3 v3.0.1
)

require (
	ariga.io/atlas v0.19.1-0.20240203083654-5948b60a8e43 // indirect
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/internal v1.10.0 // indirect
	github.com/AzureAD/microsoft-authentication-library-for-go v1.2.2 // indirect
	github.com/agext/levenshtein v1.2.1 // indirect
	github.com/antlr4-go/antlr/v4 v4.13.0 // indirect
	github.com/apparentlymart/go-textseg/v13 v13.0.0 // indirect
	github.com/avast/retry-go v3.0.0+incompatible // indirect
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/github/exception-filters/go/rules v0.3.0 // indirect
	github.com/github/go-http/v2 v2.8.2 // indirect
	github.com/github/go-reqmeta/v2 v2.1.1 // indirect
	github.com/github/otel-instrumentation-go/oteltwirp v0.2.0 // indirect
	github.com/go-errors/errors v1.5.1 // indirect
	github.com/go-jose/go-jose/v4 v4.0.2 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/go-openapi/inflect v0.19.0 // indirect
	github.com/golang-jwt/jwt/v5 v5.2.1 // indirect
	github.com/golang/protobuf v1.5.4 // indirect
	github.com/google/cel-go v0.21.0 // indirect
	github.com/google/go-cmp v0.6.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.20.0 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/hcl/v2 v2.13.0 // indirect
	github.com/klauspost/compress v1.17.10 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/matoous/go-nanoid/v2 v2.1.0 // indirect
	github.com/mitchellh/go-wordwrap v0.0.0-20150314170334-ad45545899c7 // indirect
	github.com/pkg/browser v0.0.0-20240102092130-5ac0b6a4141c // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rs/xid v1.5.0 // indirect
	github.com/sony/gobreaker v0.5.0 // indirect
	github.com/stoewer/go-strcase v1.3.0 // indirect
	github.com/sykesm/zap-logfmt v0.0.4 // indirect
	github.com/zclconf/go-cty v1.8.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.28.0 // indirect
	go.opentelemetry.io/otel/metric v1.32.0 // indirect
	go.opentelemetry.io/otel/sdk v1.28.0 // indirect
	go.opentelemetry.io/proto/otlp v1.3.1 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	golang.org/x/crypto v0.28.0 // indirect
	golang.org/x/exp v0.0.0-20240325151524-a685a6edb6d8 // indirect
	golang.org/x/mod v0.20.0 // indirect
	golang.org/x/net v0.29.0 // indirect
	golang.org/x/oauth2 v0.21.0 // indirect
	golang.org/x/sys v0.26.0 // indirect
	golang.org/x/text v0.19.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20240701130421-f6361c86f094 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20240701130421-f6361c86f094 // indirect
	google.golang.org/grpc v1.64.1 // indirect
)
