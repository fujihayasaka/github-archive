module github.com/github/notifyd

go 1.22.0
toolchain go1.22.9

require (
	firebase.google.com/go/v4 v4.15.1
	github.com/IBM/sarama v1.45.0
	github.com/Masterminds/squirrel v1.5.4
	github.com/XSAM/otelsql v0.36.0
	github.com/benbjohnson/clock v1.3.5
	github.com/emersion/go-message v0.18.2
	github.com/emersion/go-sasl v0.0.0-20220912192320-0145f2c60ead
	github.com/emersion/go-smtp v0.21.3
	github.com/emersion/go-textwrapper v0.0.0-20200911093747-65d896831594
	github.com/github/aqueduct-client-go/v2 v2.5.17
	github.com/github/authzd v0.5.3
	github.com/github/github-telemetry-go v1.32.1
	github.com/github/go-auth v0.7.2
	github.com/github/go-chatops/v2 v2.15.2
	github.com/github/go-config v1.7.2
	github.com/github/go-dbmigrator v1.1.0
	github.com/github/go-exceptions v1.1.1
	github.com/github/go-freno-client v1.0.2
	github.com/github/go-http/v2 v2.8.4
	github.com/github/go-stats v1.19.0
	github.com/github/go-twirp/v2 v2.3.5
	github.com/github/hydro-client-go/v7 v7.8.12
	github.com/github/monolith-twirp-features v1.6.0
	github.com/github/otel-instrumentation-go/oteltwirp v0.3.0
	github.com/go-sql-driver/mysql v1.8.1
	github.com/google/uuid v1.6.0
	github.com/hashicorp/go-multierror v1.1.1
	github.com/hashicorp/go-retryablehttp v0.7.7
	github.com/jmoiron/sqlx v1.4.0
	github.com/joho/godotenv v1.5.1
	github.com/microcosm-cc/bluemonday v1.0.27
	github.com/russross/blackfriday/v2 v2.1.0
	github.com/stretchr/testify v1.10.0
	github.com/tdewolff/minify/v2 v2.21.3
	github.com/twitchtv/twirp v8.1.3+incompatible
	github.com/urfave/cli/v2 v2.27.5
	go.opentelemetry.io/otel v1.34.0
	go.opentelemetry.io/otel/trace v1.34.0
	go.uber.org/zap v1.27.0
	google.golang.org/api v0.220.0
	google.golang.org/protobuf v1.36.5
)

require (
	cloud.google.com/go v0.116.0 // indirect
	cloud.google.com/go/auth v0.14.1 // indirect
	cloud.google.com/go/auth/oauth2adapt v0.2.7 // indirect
	cloud.google.com/go/compute/metadata v0.6.0 // indirect
	cloud.google.com/go/firestore v1.17.0 // indirect
	cloud.google.com/go/iam v1.2.2 // indirect
	cloud.google.com/go/longrunning v0.6.2 // indirect
	cloud.google.com/go/storage v1.43.0 // indirect
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/MicahParks/keyfunc v1.9.0 // indirect
	github.com/avast/retry-go v3.0.0+incompatible // indirect
	github.com/aymerick/douceur v0.2.0 // indirect
	github.com/cenkalti/backoff/v4 v4.3.0 // indirect
	github.com/cpuguy83/go-md2man/v2 v2.0.5 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/eapache/go-resiliency v1.7.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20230731223053-c322873962e3 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/github/exception-filters/go/rules v0.3.0 // indirect
	github.com/github/go-http v0.2.3 // indirect
	github.com/github/go-kvp v1.1.0 // indirect
	github.com/github/go-reqmeta/v2 v2.1.1 // indirect
	github.com/go-errors/errors v1.5.1 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/golang-jwt/jwt/v4 v4.5.1 // indirect
	github.com/golang-migrate/migrate/v4 v4.17.0 // indirect
	github.com/golang/groupcache v0.0.0-20210331224755-41bb18bfe9da // indirect
	github.com/golang/protobuf v1.5.4 // indirect
	github.com/golang/snappy v0.0.4 // indirect
	github.com/google/s2a-go v0.1.9 // indirect
	github.com/googleapis/enterprise-certificate-proxy v0.3.4 // indirect
	github.com/googleapis/gax-go/v2 v2.14.1 // indirect
	github.com/gorilla/css v1.0.1 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.20.0 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-uuid v1.0.3 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.7.6 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.4 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.17.11 // indirect
	github.com/lann/builder v0.0.0-20180802200727-47ae307949d0 // indirect
	github.com/lann/ps v0.0.0-20150810152359-62de8c46ede0 // indirect
	github.com/matoous/go-nanoid/v2 v2.1.0 // indirect
	github.com/mattn/go-sqlite3 v2.0.1+incompatible // indirect
	github.com/pierrec/lz4/v4 v4.1.22 // indirect
	github.com/pkg/errors v0.9.1 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20201227073835-cf1acfcdf475 // indirect
	github.com/rs/xid v1.5.0 // indirect
	github.com/sony/gobreaker v1.0.0 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	github.com/sykesm/zap-logfmt v0.0.4 // indirect
	github.com/tdewolff/parse/v2 v2.7.19 // indirect
	github.com/xrash/smetrics v0.0.0-20240521201337-686a1a2994c1 // indirect
	go.opencensus.io v0.24.0 // indirect
	go.opentelemetry.io/auto/sdk v1.1.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.58.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.58.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.28.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.28.0 // indirect
	go.opentelemetry.io/otel/metric v1.34.0 // indirect
	go.opentelemetry.io/otel/sdk v1.34.0 // indirect
	go.opentelemetry.io/proto/otlp v1.3.1 // indirect
	go.uber.org/atomic v1.10.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	golang.org/x/crypto v0.32.0 // indirect
	golang.org/x/net v0.34.0 // indirect
	golang.org/x/oauth2 v0.25.0 // indirect
	golang.org/x/sync v0.11.0 // indirect
	golang.org/x/sys v0.29.0 // indirect
	golang.org/x/text v0.21.0 // indirect
	golang.org/x/time v0.9.0 // indirect
	golang.org/x/xerrors v0.0.0-20231012003039-104605ab7028 // indirect
	google.golang.org/appengine/v2 v2.0.2 // indirect
	google.golang.org/genproto v0.0.0-20241118233622-e639e219e697 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20241209162323-e6fa225c2576 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20250127172529-29210b9bc287 // indirect
	google.golang.org/grpc v1.70.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
