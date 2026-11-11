module github.com/github/blackbird-mw

go 1.24.0

toolchain go1.24.2

require (
	github.com/cenkalti/backoff/v4 v4.3.0
	github.com/dnaeon/go-vcr v1.2.0
	github.com/github/go-auth v0.8.1
	github.com/github/go-http v0.2.3
	github.com/github/go-kvp v1.1.0
	github.com/github/go-log v1.4.5
	github.com/github/go-reqmeta v1.0.0
	github.com/github/go-stats v1.26.1
	github.com/github/go-telemetry v0.0.0-20220909163550-fb4a65294900
	github.com/github/go-twirp v0.4.1
	github.com/github/spokes-proto/gen/go v0.0.0-20240529142038-90ead863fabb
	github.com/go-redis/redis/v8 v8.11.5
	github.com/go-sql-driver/mysql v1.9.3
	github.com/golang/protobuf v1.5.4
	github.com/google/go-github v17.0.0+incompatible
	github.com/google/uuid v1.6.0
	github.com/jmoiron/sqlx v1.4.0
	github.com/kelseyhightower/envconfig v1.4.0
	github.com/pkg/errors v0.9.1
	github.com/stretchr/testify v1.11.1
	github.com/twitchtv/twirp v8.1.3+incompatible
	golang.org/x/net v0.49.0 // indirect
	google.golang.org/protobuf v1.36.11
)

require (
	github.com/IBM/sarama v1.46.3
	github.com/github/blackbird/clients/go/semantic v0.0.0-20260203201050-bd70dca9599f
	github.com/github/blackbird/crates/client v0.0.0-20260203201050-bd70dca9599f
	github.com/github/blackbird/crates/core v0.0.0-20260203201050-bd70dca9599f
	github.com/github/blackbird/crates/linguist v0.0.0-20260203201050-bd70dca9599f
	github.com/github/go-chatops/v2 v2.15.5
	github.com/github/go-chatterbox v1.5.0
	github.com/github/go-freno-client/v2 v2.0.2
	github.com/github/hydro-client-go/v7 v7.8.19
	github.com/github/hydro-schemas-go v0.0.0-20251010213001-348dfeb84406
	github.com/github/sitesapiclient v1.0.17
	github.com/go-chi/chi/v5 v5.2.4
	github.com/unrolled/secure v1.17.0
	golang.org/x/text v0.33.0
	gopkg.in/ini.v1 v1.67.1
)

require (
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/github/github-telemetry-go v1.39.2 // indirect
	github.com/github/go-http/v2 v2.8.6 // indirect
	github.com/go-logr/logr v1.4.3 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/goccy/go-yaml v1.19.2 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/pierrec/lz4/v4 v4.1.25 // indirect
	github.com/slack-go/slack v0.17.3 // indirect
	go.opentelemetry.io/auto/sdk v1.2.1 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.64.0 // indirect
	go.opentelemetry.io/otel v1.39.0 // indirect
	go.opentelemetry.io/otel/metric v1.39.0 // indirect
	go.opentelemetry.io/otel/trace v1.39.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.1 // indirect
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
	github.com/duosecurity/duo_api_golang v0.0.0-20240408132100-cb1770897e66 // indirect
	github.com/eapache/go-resiliency v1.7.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20230731223053-c322873962e3 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/golang/snappy v1.0.0 // indirect
	github.com/google/go-querystring v1.2.0 // indirect
	github.com/hashicorp/go-uuid v1.0.3 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.7.6 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.4 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.18.3 // indirect
	github.com/parkr/go-ldap-client v1.0.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20250401214520-65e299d6c5c9
	golang.org/x/crypto v0.47.0 // indirect
	golang.org/x/sync v0.19.0
	gopkg.in/asn1-ber.v1 v1.0.0-20181015200546-f715ec2f112d // indirect
	gopkg.in/ldap.v2 v2.5.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/github/blackbird-mw/pkg v0.0.0 => ./pkg
