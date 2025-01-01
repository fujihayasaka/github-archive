package snapshots

import (
	"fmt"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/util"
	"github.com/package-url/packageurl-go"
	"github.com/pkg/errors"
)

// ValidPurlTypes should be kept up to date with https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
// To see a diff since this was updated on 12/11/24: https://github.com/package-url/purl-spec/compare/1951d217bde29590a73f075db4ab71cc00011459...master
// Please also keep the date and hash in the above line up to date.
var ValidPurlTypes = util.ToSet([]string{
	"alpm", "apk", "bitbucket", "bitnami", "cocoapods", "cargo", "cocoapods", "composer", "cpan", "purl", "conan", "conda", "cran", "deb", "docker", "gem",
	"java", "generic", "github", "golang", "hackage", "hex", "huggingface", "luarocks", "maven", "mlflow", "npm", "nuget", "oci", "pub", "pypi",
	"qpkg", "rpm", "swid", "swift",
	// actions/githubactions is not officially proposed, but we use at least one if not both, so we'll need to support them anyway
	"actions", "githubactions",
	// The following are proposed, but not officially adopted yet
	"alpine", "apache", "android", "arch", "atom", "bower", "brew", "buildroot", "carthage", "chef", "chocolatey",
	"clojars", "coreos", "ctan", "crystal", "drupal", "dtype", "dub", "elm", "eclipse",
	"gitea", "gitlab", "gradle", "guix", "haxe", "helm", "julia", "melpa", "meteor", "nim", "nix", "opam",
	"openwrt", "osgi", "p2", "pear", "pecl", "perl6", "platformio", "ebuild", "puppet", "sourceforge", "sublime",
	"terraform", "vagrant", "vim", "wordpress", "yocto",
	// defunct, but included for backwards compatibility
	"lua",
})

// validatePurls returns an error on the first invalid purl in a snapshot.
func validatePurls(snapshot *interfaces.Snapshot) error {
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
