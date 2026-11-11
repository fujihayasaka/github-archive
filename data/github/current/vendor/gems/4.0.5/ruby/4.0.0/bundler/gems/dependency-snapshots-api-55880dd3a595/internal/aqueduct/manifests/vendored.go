package manifests

import "regexp"

// TODO: make this ecosystem specific rather than assuming all ecosystems can conform to the same regex

func IsVendor(file string) bool {
	return Regex.MatchString(file)
}

// This is adapted from the corresponding regex in dg-api: https://github.com/github/dependency-graph-api/blob/master/lib/vendor_regex.rb
var Regex = regexp.MustCompile(
	`^(3rd|[Tt]hird)[-_]?[Pp]arty/` +

		// Xcode
		// these can be part of a directory name
		`|\.xctemplate/` +
		`|\.imageset/` +

		// Debian packaging
		`|^debian/` +

		// C deps
		`|^deps/` +
		// TODO: enable again when c support is added
		//`|[Dd]ependencies/` +

		// Everything below here is anchored by (^|/)
		`|(^|/)(` +
		`cache/` +
		`|dist/` +

		// linters
		`|cpplint\.py` +

		// node dependencies
		`|node_modules/` +

		// yarn 2
		`|\.yarn/releases/` +
		`|\.yarn/plugins/` +
		`|\.yarn/sdks/` +
		`|\.yarn/versions/` +
		`|\.yarn/unplugged/` +

		// bower components
		`|bower_components/` +

		// erlang bundles
		`|erlang\.mk` +

		// go dependencies
		`|[Gg]odeps/_workspace/` +

		// go fixtures
		`|testdata/` +

		// vendored dependencies
		`|vendors?/` +
		`|[Ee]xtern(als?)?/` +
		`|[Vv]+endor/` +

		// bootstrap datepicker
		`|bootstrap-datepicker/` +

		// sublime text workspace files
		`|\.sublime-project` +
		`|\.sublime-workspace` +

		// vs code workspace files
		`|\.vscode/` +

		// wys editors
		`|tiny_mce/(langs|plugins|themes|utils)` +

		// ace editor
		`|ace-builds/` +

		// mathjax
		`|mathjax/` +

		// codemirror
		`|[Cc]ode[Mm]irror/(\d+\.\d+/)?(lib|mode|theme|addon|keymap|demo)` +

		//-- python --

		// sphinx
		`|docs?/_?(build|themes?|templates?|static)/` +

		// django
		`|admin_media/` +
		`|env/` +

		//-- obj-c --

		// carthage
		`|[Cc]arthage/` +

		// sparkle
		`|sparkle/` +

		// crashlytics
		`|[Cc]rashlytics\.framework/` +

		// fabric
		`|[Ff]abric\.framework/` +

		// buddybuild
		`|buddybuildsdk\.framework/` +

		// realm
		`|realm\.framework` +

		// realmswift
		`|realmswift\.framework` +

		// -- groovy --

		// gradle
		`|gradle/wrapper/` +

		// -- java --

		// maven
		`|\.mvn/wrapper/` +

		// -- .net --

		// nuget
		`|[Pp]ackages\/[^\/]+\.\d+\/` +

		// extjs
		`|extjs/\.sencha/` +
		`|extjs/docs/` +
		`|extjs/builds/` +
		`|extjs/cmd/` +
		`|extjs/examples/` +
		`|extjs/locale/` +
		`|extjs/packages/` +
		`|extjs/plugins/` +
		`|extjs/resources/` +
		`|extjs/src/` +
		`|extjs/welcome/` +

		// test fixtures
		`|[Tt]ests?/fixtures/` +
		`|[Ss]pecs?/fixtures/` +

		// r packages
		`|inst/extdata/` +

		// puphpet
		`|puphpet/` +

		// android google apis
		`|\.google_apis/` +

		// close the anchoring (
		`)`,
)
