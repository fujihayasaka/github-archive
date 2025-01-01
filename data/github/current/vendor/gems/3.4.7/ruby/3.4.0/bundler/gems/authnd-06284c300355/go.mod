module github.com/github/authnd

go 1.22.8

toolchain go1.22.10

replace github.com/github/authnd/client => ./client

require (
	github.com/DATA-DOG/go-sqlmock v1.5.0
	github.com/fatih/color v1.17.0
	github.com/github/authnd/client v0.14.1-0.20220711205545-deda646a30ea
	github.com/github/authzd v0.5.2
	github.com/github/go-auth v0.6.1
	github.com/github/go-chatops/v2 v2.15.0
	github.com/github/go-chatterbox v1.5.0
	github.com/github/go-config v1.7.2
	github.com/github/go-ctxutil v0.3.2
	github.com/github/go-exceptions v1.1.0
	github.com/github/go-http v0.2.3
	github.com/github/go-stats v1.18.1
	github.com/github/notifyd v1.6.0
	github.com/go-sql-driver/mysql v1.8.1
	github.com/golang/mock v1.6.0
	github.com/golang/protobuf v1.5.4
	github.com/google/go-querystring v1.1.0 // indirect
	github.com/google/uuid v1.6.0
	github.com/influxdata/tdigest v0.0.1
	github.com/jmoiron/sqlx v1.4.0
	github.com/justinas/alice v1.2.0
	github.com/olekukonko/tablewriter v0.0.5
	github.com/opentracing/opentracing-go v1.2.0 // indirect
	github.com/patrickmn/go-cache v2.1.0+incompatible
	github.com/pkg/errors v0.9.1
	github.com/sony/gobreaker v1.0.0
	github.com/spf13/cobra v1.8.1
	github.com/spf13/pflag v1.0.5
	github.com/stretchr/testify v1.10.0
	github.com/twirp-ecosystem/twirp-opentracing v0.4.2 // indirect
	github.com/twitchtv/twirp v8.1.3+incompatible
	github.com/vmihailenco/msgpack/v5 v5.4.1
	golang.org/x/crypto v0.31.0
	golang.org/x/oauth2 v0.21.0
	golang.org/x/term v0.27.0
	google.golang.org/protobuf v1.35.2
	gopkg.in/guregu/null.v4 v4.0.0
	gopkg.in/yaml.v2 v2.4.0
)

require (
	github.com/IBM/sarama v1.43.3
	github.com/github/github-telemetry-go v1.32.0
	github.com/github/go-dbmigrator v1.1.0
	github.com/github/go-freno-client v1.0.1
	github.com/github/go-http/v2 v2.8.2
	github.com/github/go-queryannotations v0.1.0
	github.com/github/go-reqmeta/v2 v2.1.0
	github.com/github/go-twirp/v2 v2.3.4
	github.com/github/hydro-client-go/v7 v7.8.5
	github.com/github/otel-instrumentation-go/oteltwirp v0.2.0
	github.com/golang-jwt/jwt/v5 v5.2.1
	github.com/google/go-github v17.0.0+incompatible
	github.com/lingrino/go-fault v1.0.3
	go.opentelemetry.io/otel v1.28.0
	go.opentelemetry.io/otel/trace v1.28.0
	go.uber.org/goleak v1.3.0
)

require (
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/cenkalti/backoff/v4 v4.2.1 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/duosecurity/duo_api_golang v0.0.0-20220201180708-96a8851a8448 // indirect
	github.com/eapache/go-resiliency v1.7.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20230731223053-c322873962e3 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/github/exception-filters/go/rules v0.3.0 // indirect
	github.com/github/go-kvp v1.1.0 // indirect
	github.com/go-errors/errors v1.5.1 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/golang-migrate/migrate/v4 v4.17.0 // indirect
	github.com/golang/snappy v0.0.4 // indirect
	github.com/gorilla/websocket v1.4.2 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.19.0 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-retryablehttp v0.7.7 // indirect
	github.com/hashicorp/go-uuid v1.0.3 // indirect
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.7.6 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.4 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.17.9 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mattn/go-runewidth v0.0.13 // indirect
	github.com/parkr/go-ldap-client v1.0.0 // indirect
	github.com/pierrec/lz4/v4 v4.1.21 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20201227073835-cf1acfcdf475 // indirect
	github.com/rivo/uniseg v0.2.0 // indirect
	github.com/rs/xid v1.5.0 // indirect
	github.com/slack-go/slack v0.12.2 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	github.com/sykesm/zap-logfmt v0.0.4 // indirect
	github.com/vmihailenco/tagparser/v2 v2.0.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.52.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.24.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.24.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.27.0 // indirect
	go.opentelemetry.io/otel/metric v1.28.0 // indirect
	go.opentelemetry.io/otel/sdk v1.27.0 // indirect
	go.opentelemetry.io/proto/otlp v1.1.0 // indirect
	go.uber.org/atomic v1.10.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.0 // indirect
	golang.org/x/net v0.33.0 // indirect
	golang.org/x/sys v0.28.0 // indirect
	golang.org/x/text v0.21.0 // indirect
	golang.org/x/xerrors v0.0.0-20231012003039-104605ab7028 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20240415180920-8c6c420018be // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20240429193739-8cf5692501f6 // indirect
	google.golang.org/grpc v1.63.2 // indirect
	gopkg.in/asn1-ber.v1 v1.0.0-20181015200546-f715ec2f112d // indirect
	gopkg.in/ldap.v2 v2.5.1 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
