module github.com/github/blackbird-mw

go 1.23

toolchain go1.23.2

require (
	github.com/cenkalti/backoff/v4 v4.3.0
	github.com/dnaeon/go-vcr v1.2.0
	github.com/github/go-auth v0.7.2
	github.com/github/go-http v0.2.3
	github.com/github/go-kvp v1.1.0
	github.com/github/go-log v1.4.5
	github.com/github/go-reqmeta v1.0.0
	github.com/github/go-stats v1.19.0
	github.com/github/go-telemetry v0.0.0-20220909163550-fb4a65294900
	github.com/github/go-twirp v0.4.1
	github.com/github/spokes-proto/gen/go v0.0.0-20240529142038-90ead863fabb
	github.com/go-redis/redis/v8 v8.11.5
	github.com/go-sql-driver/mysql v1.8.1
	github.com/golang/protobuf v1.5.4
	github.com/google/go-github v17.0.0+incompatible
	github.com/google/uuid v1.6.0
	github.com/jmoiron/sqlx v1.4.0
	github.com/kelseyhightower/envconfig v1.4.0
	github.com/pkg/errors v0.9.1
	github.com/stretchr/testify v1.10.0
	github.com/twitchtv/twirp v8.1.3+incompatible
	golang.org/x/net v0.35.0
	google.golang.org/protobuf v1.36.5
)

require (
	github.com/IBM/sarama v1.45.0
	github.com/github/blackbird/clients/go/semantic v0.0.0-20250122221330-a1fc92b0b8ac
	github.com/github/blackbird/crates/client v0.0.0-20250114203548-612d904c37f9
	github.com/github/blackbird/crates/core v0.0.0-20250114203548-612d904c37f9
	github.com/github/blackbird/crates/linguist v0.0.0-20250114203548-612d904c37f9
	github.com/github/go-chatops/v2 v2.15.2
	github.com/github/go-chatterbox v1.5.0
	github.com/github/go-freno-client v1.0.2
	github.com/github/hydro-client-go/v7 v7.8.12
	github.com/github/hydro-schemas-go v0.0.0-20250109000017-a704ebec8692
	github.com/github/sitesapiclient v1.0.7
	github.com/go-chi/chi/v5 v5.2.1
	github.com/unrolled/secure v1.17.0
	golang.org/x/text v0.22.0
	gopkg.in/ini.v1 v1.67.0
)

require (
	filippo.io/edwards25519 v1.1.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/pierrec/lz4/v4 v4.1.22 // indirect
	github.com/slack-go/slack v0.16.0 // indirect
	go.opentelemetry.io/auto/sdk v1.1.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.59.0 // indirect
	go.opentelemetry.io/otel v1.34.0 // indirect
	go.opentelemetry.io/otel/metric v1.34.0 // indirect
	go.opentelemetry.io/otel/trace v1.34.0 // indirect
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
	github.com/duosecurity/duo_api_golang v0.0.0-20240408132100-cb1770897e66 // indirect
	github.com/eapache/go-resiliency v1.7.0 // indirect
	github.com/eapache/go-xerial-snappy v0.0.0-20230731223053-c322873962e3 // indirect
	github.com/eapache/queue v1.1.0 // indirect
	github.com/golang/snappy v0.0.4 // indirect
	github.com/google/go-querystring v1.1.0 // indirect
	github.com/hashicorp/go-uuid v1.0.3 // indirect
	github.com/jcmturner/aescts/v2 v2.0.0 // indirect
	github.com/jcmturner/dnsutils/v2 v2.0.0 // indirect
	github.com/jcmturner/gofork v1.7.6 // indirect
	github.com/jcmturner/gokrb5/v8 v8.4.4 // indirect
	github.com/jcmturner/rpc/v2 v2.0.3 // indirect
	github.com/klauspost/compress v1.17.11 // indirect
	github.com/parkr/go-ldap-client v1.0.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/rcrowley/go-metrics v0.0.0-20201227073835-cf1acfcdf475
	golang.org/x/crypto v0.33.0 // indirect
	golang.org/x/sync v0.11.0
	gopkg.in/asn1-ber.v1 v1.0.0-20181015200546-f715ec2f112d // indirect
	gopkg.in/ldap.v2 v2.5.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/github/blackbird-mw/pkg v0.0.0 => ./pkg
