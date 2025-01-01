package gorules

import (
	"github.com/quasilyte/go-ruleguard/dsl"
)

// This file implements the rules for the go-ruleguard package,
// This is run by golangci-lint via the gocritic linter with the ruleguard check
// After changing these rules, run `golangci-lint cache clean` before `script/lint`
// These rules can also be run manually with the `ruleguard` command
// https://github.com/quasilyte/go-ruleguard#quick-start

// These rules are called dynamically by ruleguard
//
//nolint:deadcode,unused
func callToEncodeGlobalID(m dsl.Matcher) {
	m.Match(`testutils.EncodeGlobalID`).
		Where(!m.File().Name.Matches("_test\\.go$")).
		Report(`call to testutils.EncodeGlobalID in non-test file`)
}

//nolint:deadcode,unused
func callToEncodeGlobalIDString(m dsl.Matcher) {
	m.Match(`testutils.EncodeGlobalIDString`).
		Where(!m.File().Name.Matches("_test\\.go$")).
		Report(`call to testutils.EncodeGlobalIDString in non-test file`)
}

//nolint:deadcode,unused
func callToSetLaunchConfigEnv(m dsl.Matcher) {
	m.Match(`testutils.SetLaunchConfigEnv`).
		Where(!m.File().Name.Matches("_test\\.go$")).
		Report(`call to testutils.SetLaunchConfigEnv in non-test file`)
}

//nolint:deadcode,unused
func callToSetAppMode(m dsl.Matcher) {
	m.Match(`testutils.SetAppMode`).
		Where(!m.File().Name.Matches("_test\\.go$")).
		Report(`call to testutils.SetAppMode in non-test file`)
}

//nolint:deadcode,unused
func callToResetConfig(m dsl.Matcher) {
	m.Match(`launchconfig.ResetConfig`).
		Where(!m.File().PkgPath.Matches("^github.com/github/launch/utils/testutils")).
		Report(`call to launchconfig.ResetConfig outside of testutils`)
}

//nolint:deadcode,unused
func callToAppHTTP(m dsl.Matcher) {
	m.Match(`apphttp.$_`).
		Where(
			!m.File().Name.Matches("_test\\.go$") &&
				!m.File().Name.Matches("^test_factory\\.go$") &&
				!m.File().Name.Matches("^test_utils\\.go$") &&
				!m.File().PkgPath.Matches("^github.com/github/launch/cmd.*$") &&
				!(m.File().PkgPath.Matches("github.com/github/launch/pkg/launchchaos") &&
					m.File().Name.Matches("setup.go")) &&
				!(m.File().PkgPath.Matches("github.com/github/launch/services/hydrosvc") &&
					m.File().Name.Matches("service.go")),
		).
		Report(`call to apphttp outside of app instantiation`)
}

//nolint:deadcode,unused
func callToCreateHTTPClient(m dsl.Matcher) {
	m.Match(`http.Client{}`).
		Where(!(m.File().Name.Matches("_test\\.go$") || m.File().Name.Matches("apphttp.go"))).
		Report(`call to create http.Client in non-test file`)
}

//nolint:deadcode,unused
func callToAssertNoError(m dsl.Matcher) {
	m.Match(`assert.NoError`).
		Where(m.File().Name.Matches("_test\\.go$")).
		Report(`call to assert.NoError, prefer require.NoError`)
}

//nolint:deadcode,unused
func globalIDTypeConversion(m dsl.Matcher) {
	m.Import("github.com/github/launch/types")

	m.Match(`types.GlobalID($_)`).
		Where(!m.File().Name.Matches("_test\\.go$")).
		Report(`Use types.NewGlobalID instead of a type conversion until the global id migration is complete`)
}

//nolint:deadcode,unused
func callToHTTPUtilDumpRequest(m dsl.Matcher) {
	m.Import("github.com/github/launch/types")

	m.Match(`httputil.DumpRequest`).
		Where(!m.File().Name.Matches("stringutils\\.go")).
		Report(`httputil.DumpRequest should not be used directly for logging, use stringutils.HTTPRequestToString instead`)
}

//nolint:deadcode,unused
func callToSetTracer(m dsl.Matcher) {
	m.Import("github.com/github/launch/observability/tracing")

	m.Match(`tracing.SetTestTracer`).
		Where(!m.File().Name.Matches("_test\\.go$") && !m.File().PkgPath.Matches("^github.com/github/launch/utils/testutils")).
		Report(`call to tracing.SetTestTracer in non-test file`)
}
