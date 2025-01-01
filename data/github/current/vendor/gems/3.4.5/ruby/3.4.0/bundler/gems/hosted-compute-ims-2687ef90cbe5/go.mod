module github.com/github/hosted-compute-ims

go 1.23.8

require (
	buf.build/gen/go/bufbuild/protovalidate/protocolbuffers/go v1.36.6-20250307204501-0409229c3780.1
	entgo.io/ent v0.14.4
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.18.0
	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.10.0
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5 v5.7.0
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources v1.2.0
	github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage v1.8.0
	github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v1.6.1
	github.com/Masterminds/semver v1.5.0
	github.com/bufbuild/protovalidate-go v0.9.2
	github.com/coreos/go-oidc/v3 v3.14.1
	github.com/github/aqueduct-client-go/v2 v2.5.19
	github.com/github/feature-management-client-go/vexi v1.9.3
	github.com/github/github-telemetry-go v1.34.0
	github.com/github/go-auth v0.7.2
	github.com/github/go-config v1.7.2
	github.com/github/go-exceptions v1.2.2
	github.com/github/go-http v0.2.3
	github.com/github/go-http/v2 v2.8.4
	github.com/github/go-stats v1.20.0
	github.com/github/go-twirp/v2 v2.3.6
	github.com/github/hosted-compute-core/asymmjwt v0.0.0-20250408185832-44a3f0270659
	github.com/github/hosted-compute-core/cryptography v0.0.0-20250408185832-44a3f0270659
	github.com/github/hosted-compute-core/oidc v0.0.0-20250408185832-44a3f0270659
	github.com/github/hosted-compute-core/telemetry v0.0.0-20250408185832-44a3f0270659
	github.com/github/hydro-schemas-go v0.0.0-20250422135258-f13f281c9bcc
	github.com/github/maccloud-go-core/maccloud v0.2.2
	github.com/github/monolith-twirp-features v1.6.0
	github.com/go-sql-driver/mysql v1.9.2
	github.com/golang-jwt/jwt/v4 v4.5.2
	github.com/golang/protobuf v1.5.3
	github.com/google/uuid v1.6.0
	github.com/jmoiron/sqlx v1.4.0
	github.com/patrickmn/go-cache v2.1.0+incompatible
	github.com/pkg/errors v0.9.1
	github.com/stretchr/testify v1.10.0
	github.com/twitchtv/twirp v8.1.3+incompatible
	github.com/ugorji/go/codec v1.2.12
	go.opentelemetry.io/otel v1.35.0
	go.opentelemetry.io/otel/trace v1.35.0
	go.uber.org/mock v0.5.2
	go.uber.org/zap v1.27.0
	google.golang.org/protobuf v1.36.6
	gopkg.in/yaml.v3 v3.0.1
)

require (
	ariga.io/atlas v0.31.1-0.20250212144724-069be8033e83 // indirect
	cel.dev/expr v0.19.1 // indirect
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/internal v1.11.1 // indirect
	github.com/AzureAD/microsoft-authentication-library-for-go v1.4.2 // indirect
	github.com/IBM/sarama v1.45.0 // indirect
	github.com/MicahParks/jwkset v0.8.0 // indirect
	github.com/MicahParks/keyfunc/v3 v3.3.10 // indirect
	github.com/agext/levenshtein v1.2.1 // indirect
	github.com/antlr4-go/antlr/v4 v4.13.0 // indirect
	github.com/apparentlymart/go-textseg/v13 v13.0.0 // indirect
	github.com/apparentlymart/go-textseg/v15 v15.0.0 // indirect
	github.com/avast/retry-go v3.0.0+incompatible // indirect
	github.com/avast/retry-go/v4 v4.6.1 // indirect
	github.com/bmatcuk/doublestar v1.3.4 // indirect
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/eapache/go-resiliency v1.7.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20230731223053-c322873962e3 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/github/exception-filters/go/rules v0.3.0 // indirect
	github.com/github/feature-management-protos/gen/go/feature_management/feature_flags v1.7.6 // indirect
	github.com/github/go-reqmeta/v2 v2.1.2 // indirect
	github.com/github/hydro-client-go/v7 v7.8.12 // indirect
	github.com/github/otel-instrumentation-go/oteltwirp v0.3.0 // indirect
	github.com/go-errors/errors v1.5.1 // indirect
	github.com/go-jose/go-jose/v4 v4.0.5 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/go-openapi/inflect v0.19.0 // indirect
	github.com/golang-jwt/jwt/v5 v5.2.2 // indirect
	github.com/golang/mock v1.6.0 // indirect
	github.com/golang/snappy v0.0.4 // indirect
	github.com/google/cel-go v0.23.2 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.23.0 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-uuid v1.0.3 // indirect
	github.com/hashicorp/hcl/v2 v2.13.0 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.7.6 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.4 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.17.11 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/matoous/go-nanoid/v2 v2.1.0 // indirect
	github.com/mitchellh/go-wordwrap v0.0.0-20150314170334-ad45545899c7 // indirect
	github.com/pierrec/lz4/v4 v4.1.22 // indirect
	github.com/pkg/browser v0.0.0-20240102092130-5ac0b6a4141c // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/puzpuzpuz/xsync/v3 v3.5.1 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20201227073835-cf1acfcdf475 // indirect
	github.com/rs/xid v1.6.0 // indirect
	github.com/sony/gobreaker v1.0.0 // indirect
	github.com/stoewer/go-strcase v1.3.0 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	github.com/sykesm/zap-logfmt v0.0.4 // indirect
	github.com/zclconf/go-cty v1.14.4 // indirect
	github.com/zclconf/go-cty-yaml v1.1.0 // indirect
	go.opentelemetry.io/auto/sdk v1.1.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.60.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.32.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.32.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.32.0 // indirect
	go.opentelemetry.io/otel/metric v1.35.0 // indirect
	go.opentelemetry.io/otel/sdk v1.35.0 // indirect
	go.opentelemetry.io/proto/otlp v1.3.1 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	golang.org/x/crypto v0.38.0 // indirect
	golang.org/x/exp v0.0.0-20240909161429-701f63a606c0 // indirect
	golang.org/x/mod v0.23.0 // indirect
	golang.org/x/net v0.40.0 // indirect
	golang.org/x/oauth2 v0.28.0 // indirect
	golang.org/x/sync v0.14.0 // indirect
	golang.org/x/sys v0.33.0 // indirect
	golang.org/x/text v0.25.0 // indirect
	golang.org/x/time v0.9.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20250106144421-5f5ef82da422 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20250102185135-69823020774d // indirect
	google.golang.org/grpc v1.67.1 // indirect
)
