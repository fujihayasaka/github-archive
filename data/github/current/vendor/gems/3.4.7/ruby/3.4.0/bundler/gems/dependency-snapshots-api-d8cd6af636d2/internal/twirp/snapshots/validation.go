package snapshots

import (
	"context"
	"fmt"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/util"
	"github.com/package-url/packageurl-go"
	"github.com/pkg/errors"
)

// ValidPurlTypes should be kept up to date with https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst
// To see a diff since this was updated on July 17, 2025: https://github.com/package-url/purl-spec/compare/c29b870ab33382309eefee2a0975ef7f71fdb742...main
// Please also keep the date and hash in the above line up to date.
var ValidPurlTypes = util.ToSet([]string{
	"alpm", "apk", "bitbucket", "bitnami", "cargo", "cocoapods", "composer", "cpan", "conan", "conda", "cran", "deb", "docker", "gem",
	"generic", "github", "golang", "hackage", "hex", "huggingface", "java", "luarocks", "maven", "mlflow", "npm", "nuget", "oci", "pub",
	"purl", "pypi", "qpkg", "rpm", "swid", "swift",
	// actions/githubactions is not officially proposed, but we use at least one if not both, so we'll need to support them anyway
	"actions", "githubactions",
	// The following are proposed, but not officially adopted yet
	"alpine", "android", "apache", "arch", "atom", "bower", "brew", "buildroot", "carthage", "chef", "chocolatey",
	"clojars", "coreos", "ctan", "crystal", "drupal", "dtype", "dub", "ebuild", "eclipse",
	"gitea", "gitlab", "gradle", "guix", "haxe", "helm", "julia", "melpa", "meteor", "nim", "nix", "opam",
	"openwrt", "osgi", "p2", "pear", "pecl", "perl6", "platformio", "puppet", "sourceforge", "sublime",
	"terraform", "vagrant", "vim", "wordpress", "yocto",
	// defunct, but included for backwards compatibility
	"elm", "lua",
})

// validatePurls returns an error on the first invalid purl in a snapshot.
func validatePurls(ctx context.Context, snapshot *interfaces.Snapshot) error {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CreateDependencySnapshot", "validatePurls")
	defer ender()
	for _, manifest := range snapshot.Manifests {
		for _, dep := range manifest.Resolved {
			err := ValidatePurl(dep.PackageURL)
			if err != nil {
				// We don't want an unreasonably long error so truncate the
				// invalid string if it's much longer than a normal purl
				return errors.Wrapf(err, "in manifest %q decoding %q", manifest.Name, util.Truncate(dep.PackageURL, 200))
			}
		}
	}
	return nil
}

// ValidatePurl returns an error if the given purl is structurally invalid -or- if it does not have a known type.
func ValidatePurl(purlString string) error {
	purl, err := packageurl.FromString(purlString)
	if err != nil {
		return err
	}
	t := purl.Type
	if !ValidPurlTypes.Contains(t) {
		return fmt.Errorf("invalid package url type: %s", t)
	}
	return nil
}
