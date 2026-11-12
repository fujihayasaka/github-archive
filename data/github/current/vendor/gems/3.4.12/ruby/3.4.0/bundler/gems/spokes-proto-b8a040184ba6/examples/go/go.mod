module github.com/github/spokes-api/examples/go

go 1.16

require (
	github.com/github/go-auth v0.2.0
	github.com/github/go/http v0.1.3
	github.com/github/spokes-proto/gen/go v0.0.0-dev
)

replace github.com/github/spokes-proto/gen/go v0.0.0-dev => ../../gen/go
