module github.com/github/billing-platform

go 1.23.4

require (
	github.com/Azure/azure-kusto-go/azkustodata v1.0.0-preview-5
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.17.0
	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.8.0
	github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos v1.2.0
	github.com/Azure/azure-sdk-for-go/sdk/data/aztables v1.3.0
	github.com/Azure/azure-sdk-for-go/sdk/keyvault/azsecrets v0.12.0
	github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v1.5.0
	github.com/Azure/azure-sdk-for-go/sdk/storage/azqueue v1.0.0
	github.com/Azure/azure-sdk-for-go/sdk/tracing/azotel v0.4.0
	github.com/IBM/sarama v1.45.0
	github.com/github/aqueduct-client-go/v2 v2.5.13
	github.com/github/feature-management-client-go/vexi v1.5.2
	github.com/github/github-telemetry-go v1.32.1
	github.com/github/go-auth v0.7.2
	github.com/github/go-config v1.7.2
	github.com/github/go-ctxutil v0.3.3
	github.com/github/go-exceptions v1.1.1
	github.com/github/go-http/v2 v2.8.4
	github.com/github/go-stats v1.19.0
	github.com/github/go-twirp/v2 v2.3.5
	github.com/github/hydro-client-go/v7 v7.8.9
	github.com/github/monolith-twirp-billing v1.1.1
	github.com/go-co-op/gocron v1.37.0
	github.com/golang/protobuf v1.5.4
	github.com/google/uuid v1.6.0
	github.com/gorilla/csrf v1.7.2
	github.com/onsi/gomega v1.36.2
	github.com/opentracing/opentracing-go v1.2.0
	github.com/pkg/errors v0.9.1
	github.com/shopspring/decimal v1.4.0
	github.com/twirp-ecosystem/twirp-opentracing v0.4.2
	github.com/twitchtv/twirp v8.1.3+incompatible
	go.opentelemetry.io/otel v1.34.0
	go.opentelemetry.io/otel/bridge/opentracing v1.33.0
	golang.org/x/oauth2 v0.25.0
	golang.org/x/sync v0.10.0
	google.golang.org/protobuf v1.36.4
)

require github.com/benbjohnson/clock v1.3.5 // indirect

require (
	github.com/avast/retry-go/v4 v4.6.0 // indirect
	github.com/github/feature-management-protos/gen/go/feature_management/feature_flags v1.7.4 // indirect
	github.com/github/otel-instrumentation-go/oteltwirp v0.2.0 // indirect
	github.com/golang-jwt/jwt/v5 v5.2.1 // indirect
	github.com/golang/mock v1.6.0 // indirect
	github.com/gorilla/securecookie v1.1.2 // indirect
	github.com/puzpuzpuz/xsync/v3 v3.5.0 // indirect
	github.com/samber/lo v1.47.0 // indirect
	github.com/sony/gobreaker v1.0.0 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	go.opentelemetry.io/auto/sdk v1.1.0 // indirect
	go.opentelemetry.io/otel/metric v1.34.0 // indirect
	golang.org/x/exp v0.0.0-20240909161429-701f63a606c0 // indirect
	golang.org/x/tools v0.29.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20250106144421-5f5ef82da422 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20250106144421-5f5ef82da422 // indirect
)

require (
	github.com/Azure/azure-sdk-for-go v68.0.0+incompatible // indirect
	github.com/Azure/azure-sdk-for-go/sdk/internal v1.10.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/keyvault/internal v0.7.1 // indirect
	github.com/AzureAD/microsoft-authentication-library-for-go v1.3.2 // indirect
	github.com/avast/retry-go v3.0.0+incompatible // indirect
	github.com/carmark/pseudo-terminal-go v0.0.0-20151106093136-5a48ae24c6f5
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/eapache/go-resiliency v1.7.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20230731223053-c322873962e3 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/github/exception-filters/go/rules v0.3.0 // indirect
	github.com/github/go-reqmeta/v2 v2.1.2 // indirect
	github.com/go-errors/errors v1.5.1 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/golang/snappy v0.0.4 // indirect
	github.com/google/go-cmp v0.6.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.25.1 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-uuid v1.0.3 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.7.6 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.4 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.17.11 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/matoous/go-nanoid/v2 v2.1.0 // indirect
	github.com/mattn/go-colorable v0.1.14
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/neilotoole/jsoncolor v0.7.1
	github.com/petergtz/pegomock/v4 v4.1.0
	github.com/pierrec/lz4/v4 v4.1.22 // indirect
	github.com/pkg/browser v0.0.0-20240102092130-5ac0b6a4141c // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20201227073835-cf1acfcdf475 // indirect
	github.com/robfig/cron/v3 v3.0.1 // indirect
	github.com/rs/cors v1.11.1
	github.com/rs/xid v1.6.0 // indirect
	github.com/segmentio/encoding v0.4.1 // indirect
	github.com/stretchr/testify v1.10.0
	github.com/sykesm/zap-logfmt v0.0.4 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.33.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.33.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.33.0 // indirect
	go.opentelemetry.io/otel/sdk v1.33.0 // indirect
	go.opentelemetry.io/otel/trace v1.34.0
	go.opentelemetry.io/proto/otlp v1.5.0 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/ratelimit v0.3.1
	go.uber.org/zap v1.27.0
	golang.org/x/crypto v0.32.0 // indirect
	golang.org/x/net v0.34.0 // indirect
	golang.org/x/sys v0.29.0 // indirect
	golang.org/x/term v0.28.0 // indirect
	golang.org/x/text v0.21.0 // indirect
	google.golang.org/grpc v1.69.2 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
