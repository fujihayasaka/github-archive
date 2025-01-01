module github.com/github/billing-platform

go 1.22.2

require (
	github.com/Azure/azure-kusto-go/azkustodata v1.0.0-preview-2
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.16.0
	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.7.0
	github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos v1.1.1-0.20241031215045-12965bcb1bc1
	github.com/Azure/azure-sdk-for-go/sdk/data/aztables v1.0.1
	github.com/Azure/azure-sdk-for-go/sdk/keyvault/azsecrets v0.12.0
	github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v1.3.2
	github.com/Azure/azure-sdk-for-go/sdk/storage/azqueue v1.0.0
	github.com/Azure/azure-sdk-for-go/sdk/tracing/azotel v0.4.0
	github.com/Shopify/sarama v1.34.1
	github.com/github/aqueduct-client-go/v2 v2.0.5
	github.com/github/github-telemetry-go v1.26.3
	github.com/github/go-auth v0.3.0
	github.com/github/go-config v1.6.5
	github.com/github/go-ctxutil v0.3.2
	github.com/github/go-exceptions v0.17.1
	github.com/github/go-http/v2 v2.4.3
	github.com/github/go-stats v1.14.0
	github.com/github/go-twirp/v2 v2.3.2
	github.com/github/hydro-client-go/v5 v5.4.0
	github.com/github/monolith-twirp-billing v1.0.1
	github.com/github/monolith-twirp-features v1.2.5
	github.com/go-co-op/gocron v1.28.0
	github.com/golang/protobuf v1.5.3
	github.com/google/uuid v1.6.0
	github.com/gorilla/csrf v1.7.2
	github.com/onsi/gomega v1.27.6
	github.com/opentracing/opentracing-go v1.2.0
	github.com/pkg/errors v0.9.1
	github.com/shopspring/decimal v1.3.1
	github.com/twirp-ecosystem/twirp-opentracing v0.4.2
	github.com/twitchtv/twirp v8.1.3+incompatible
	go.opentelemetry.io/otel v1.16.0
	go.opentelemetry.io/otel/bridge/opentracing v1.15.0
	golang.org/x/oauth2 v0.8.0
	golang.org/x/sync v0.8.0
	google.golang.org/protobuf v1.33.0
)

require github.com/benbjohnson/clock v1.3.3 // indirect

require (
	github.com/golang-jwt/jwt/v5 v5.2.1 // indirect
	github.com/gorilla/securecookie v1.1.2 // indirect
	github.com/samber/lo v1.39.0 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	go.opentelemetry.io/otel/metric v1.16.0 // indirect
	golang.org/x/exp v0.0.0-20240222234643-814bf88cf225 // indirect
)

require (
	github.com/Azure/azure-sdk-for-go v68.0.0+incompatible // indirect
	github.com/Azure/azure-sdk-for-go/sdk/internal v1.10.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/keyvault/internal v0.7.1 // indirect
	github.com/AzureAD/microsoft-authentication-library-for-go v1.2.2 // indirect
	github.com/avast/retry-go v3.0.0+incompatible // indirect
	github.com/carmark/pseudo-terminal-go v0.0.0-20151106093136-5a48ae24c6f5
	github.com/cenkalti/backoff/v4 v4.2.1 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/eapache/go-resiliency v1.2.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20180814174437-776d5712da21 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/github/exception-filters/go/rules v0.3.0 // indirect
	github.com/github/go-reqmeta/v2 v2.0.4 // indirect
	github.com/go-errors/errors v1.4.2 // indirect
	github.com/go-logr/logr v1.2.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/golang/snappy v0.0.4 // indirect
	github.com/google/go-cmp v0.5.9 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.15.2 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-uuid v1.0.2 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.0.0 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.2 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.15.6 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/matoous/go-nanoid/v2 v2.0.0 // indirect
	github.com/mattn/go-colorable v0.1.13
	github.com/mattn/go-isatty v0.0.16 // indirect
	github.com/neilotoole/jsoncolor v0.6.0
	github.com/petergtz/pegomock/v4 v4.1.0
	github.com/pierrec/lz4/v4 v4.1.17 // indirect
	github.com/pkg/browser v0.0.0-20240102092130-5ac0b6a4141c // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20201227073835-cf1acfcdf475 // indirect
	github.com/robfig/cron/v3 v3.0.1 // indirect
	github.com/rs/cors v1.11.0
	github.com/rs/xid v1.5.0 // indirect
	github.com/segmentio/encoding v0.1.14 // indirect
	github.com/stretchr/testify v1.9.0
	github.com/sykesm/zap-logfmt v0.0.4 // indirect
	go.opentelemetry.io/contrib/propagators/ot v1.16.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/internal/retry v1.15.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.15.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.15.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.15.0 // indirect
	go.opentelemetry.io/otel/sdk v1.16.0 // indirect
	go.opentelemetry.io/otel/trace v1.16.0
	go.opentelemetry.io/proto/otlp v0.19.0 // indirect
	go.uber.org/atomic v1.10.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/ratelimit v0.3.1
	go.uber.org/zap v1.24.0
	golang.org/x/crypto v0.27.0 // indirect
	golang.org/x/net v0.29.0 // indirect
	golang.org/x/sys v0.25.0 // indirect
	golang.org/x/term v0.24.0 // indirect
	golang.org/x/text v0.18.0 // indirect
	google.golang.org/appengine v1.6.7 // indirect
	google.golang.org/genproto v0.0.0-20230410155749-daa745c078e1 // indirect
	google.golang.org/grpc v1.56.3 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
