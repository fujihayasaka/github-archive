// manifests is a package **internal to the aqueduct package** that defines types and functions related to dependency manifests and graph changes.
// It should not be confused with the manifest type that is embedded in dependency snapshots.
// These types are used within the aqueduct package for communication with other services.
package manifests

import (
	"path/filepath"
	"regexp"
	"strings"

	"github.com/github/dependency-snapshots-api/internal/ecosystems"
)

// Regex patterns for detecting Python requirements.txt manifest variants.
// Ported from github/github's DependencyManifestFile model.
//
// REQUIREMENTS_TXT_PATTERN: matches "requirements" preceded by a hyphen, period,
// underscore, start-of-string, or slash, followed by non-whitespace chars and ".txt".
// Examples: requirements.txt, requirements.prod.txt, requirements/production.txt
var requirementsTxtPattern = regexp.MustCompile(`(?i)(?:[-._]|^|/)requirements[^\s]*\.txt$`)

// REQUIRE_TXT_PATTERN: more lenient, matches "require" with optional prefix (no dots/whitespace)
// and optional hyphen/underscore/slash suffix. Does not match "require" as a substring
// (e.g. "required.txt" is rejected).
// Examples: require.txt, require-test.txt, py3-require.txt, pyenv_require_e2e.txt
var requireTxtPattern = regexp.MustCompile(`(?i)[^\s|.]*require(?:[-_/][^\s|.]*)?\.txt$`)

// when a file path is matched as a supported manifest type,
// this well formed scoping metadata is returned to the caller
type Info struct {
	Path       string
	Name       string
	Ecosystem  ecosystems.Ecosystem
	FileType   FileType
	IsVendored bool
	IsPreview  bool
}

// A ManifestMapping uses an ordered list of manifestClassifier to
// determine the ecosystem and file type of a manifest file, if
// possible.
type ManifestMapping []manifestClassifier

type manifestClassifier struct {
	predicate func(string) bool
	fileType  FileType
	ecosystem ecosystems.Ecosystem
}

// Recognize returns the ecosystem and file type of a manifest file, plus
// a boolean indicating whether the file was successfully recognized.
func (mm ManifestMapping) Recognize(fullPath string) (ecosystems.Ecosystem, FileType, bool) {
	for _, mc := range mm {
		if mc.predicate(fullPath) {
			return mc.ecosystem, mc.fileType, true
		}
	}
	return ecosystems.Unknown, UnknownFileType, false
}

// mapping of file types in "supported" status to parent ecosystems
var DefaultMappings = ManifestMapping{
	// npm
	NewFileTypeMappingClassifier(PackageJSON, ecosystems.NPM),
	NewFileTypeMappingClassifier(PackageLockJSON, ecosystems.NPM),
	NewFileTypeMappingClassifier(YarnLock, ecosystems.NPM),
	NewFileTypeMappingClassifier(PNPMLock, ecosystems.NPM),

	// Go
	NewFileTypeMappingClassifier(GoMod, ecosystems.Golang),
	NewFileTypeMappingClassifier(GoSum, ecosystems.Golang),

	// Python
	NewRegexMappingClassifier(requirementsTxtPattern, RequirementsTxt, ecosystems.PyPi),
	NewRegexMappingClassifier(requireTxtPattern, RequirementsTxt, ecosystems.PyPi),
	NewFileTypeMappingClassifier(Pipfile, ecosystems.PyPi),
	NewFileTypeMappingClassifier(PipfileLock, ecosystems.PyPi),
	NewFileTypeMappingClassifier(SetupPy, ecosystems.PyPi),
	NewFileTypeMappingClassifier(PyprojectToml, ecosystems.PyPi),
	NewFileTypeMappingClassifier(PoetryLock, ecosystems.PyPi),
	NewFileTypeMappingClassifier(UvLock, ecosystems.PyPi),
}

// mapping of file types in "preview" status (in the process
// of being tested and rollout out as a supported type) to
// parent ecosystems
var PreviewMappings = ManifestMapping{}

// NewFileTypeMappingClassifier returns a manifestClassifier for a given file
// name and ecosystem. The returned manifestClassifier will match the given file
// name exactly, but it will discard the file path before matching.
//
// This should be used for any file type that can be recognized based on an exact
// (case-insensitive) string match. For anything that requires more complex logic,
// use a custom manifestClassifier.
func NewFileTypeMappingClassifier(fileType FileType, ecosystem ecosystems.Ecosystem) manifestClassifier {
	return manifestClassifier{
		ecosystem: ecosystem,
		fileType:  fileType,
		predicate: func(fullPath string) bool {
			fileName := strings.ToLower(filepath.Base(fullPath))
			fileExt := strings.ToLower(filepath.Ext(fullPath))
			return (fileName == fileType.String()) || (fileExt == fileType.String())
		},
	}
}

// NewRegexMappingClassifier returns a manifestClassifier that matches using a
// compiled regular expression against the full file path. This is used for
// manifest types with irregular naming conventions (e.g. Python requirements.txt
// variants like "requirements.prod.txt" or "py3-require.txt").
func NewRegexMappingClassifier(pattern *regexp.Regexp, fileType FileType, ecosystem ecosystems.Ecosystem) manifestClassifier {
	return manifestClassifier{
		ecosystem: ecosystem,
		fileType:  fileType,
		predicate: func(fullPath string) bool {
			return pattern.MatchString(fullPath)
		},
	}
}

// returns true, and manifest classification metadata, if this is a
// supported manifest type.
func ClassifyManifest(file string) (Info, bool) {
	path := filepath.Dir(file)
	name := filepath.Base(file)

	// is this file a supported manifest type we should process?
	eco, fileType, found := DefaultMappings.Recognize(file)
	if found {
		return Info{
			Path:       path,
			Name:       name,
			Ecosystem:  eco,
			FileType:   fileType,
			IsVendored: IsVendor(file),
			IsPreview:  false,
		}, true
	}

	// is this file a manifest type in "preview" status?
	// TODO: something more clever to support DGv2 previews
	eco, fileType, found = PreviewMappings.Recognize(file)
	if found {
		return Info{
			Path:       path,
			Name:       name,
			Ecosystem:  eco,
			FileType:   fileType,
			IsVendored: IsVendor(file),
			IsPreview:  true,
		}, true
	}

	return Info{}, false
}

// enumeration of manifest file types
type FileType uint32

func (ft FileType) String() string {
	switch ft {
	case PackageJSON:
		return packageJSONStr

	case PackageLockJSON:
		return packageLockJSONStr

	case YarnLock:
		return yarnLockStr

	case PNPMLock:
		return pnpmLockStr

	case PomXML:
		return pomXMLStr

	case BuildGradle:
		return buildGradleStr

	case BuildGradleKts:
		return buildGradleKtsStr

	case GradleWrapper:
		return gradleWrapperStr

	case GoMod:
		return goModStr

	case GoSum:
		return goSumStr

	case Sln:
		return slnStr

	case Csproj:
		return csprojStr

	case PackagesConfig:
		return packagesConfigStr

	case Vbproj:
		return vbprojStr

	case Vcxproj:
		return vcxprojStr

	case Fsproj:
		return fsprojStr

	case RequirementsTxt:
		return requirementsTxtStr

	case Pipfile:
		return pipfileStr

	case PipfileLock:
		return pipfileLockStr

	case SetupPy:
		return setupPyStr

	case PyprojectToml:
		return pyprojectTomlStr

	case PoetryLock:
		return poetryLockStr

	case UvLock:
		return uvLockStr

	// case NextSupportedManifestTypeHere: ...

	default:
	}

	return unknownFileTypeStr
}

const (
	UnknownFileType FileType = iota

	// NPM file types
	PackageJSON
	PackageLockJSON
	YarnLock
	PNPMLock

	// Maven file types
	PomXML

	// Gradle file types
	BuildGradle
	BuildGradleKts
	GradleWrapper

	// Golang file types
	GoMod
	GoSum

	// NuGet file types
	Sln
	Csproj
	PackagesConfig
	Vbproj
	Vcxproj
	Fsproj

	// PyPI file types
	RequirementsTxt
	Pipfile
	PipfileLock
	SetupPy
	PyprojectToml
	PoetryLock
	UvLock

	// add next supported manifest file type here
)

const (
	unknownFileTypeStr = "UNKNOWN"

	// NPM file types
	packageJSONStr     = "package.json"
	packageLockJSONStr = "package-lock.json"
	yarnLockStr        = "yarn.lock"
	pnpmLockStr        = "pnpm-lock.yaml"

	// Maven file types
	pomXMLStr = "pom.xml"

	// Gradle file types
	buildGradleStr    = "build.gradle"
	buildGradleKtsStr = "build.gradle.kts"
	gradleWrapperStr  = "gradlew"

	// Golang file types
	goModStr = "go.mod"
	goSumStr = "go.sum"

	// NuGet file types
	slnStr            = ".sln"
	csprojStr         = ".csproj"
	packagesConfigStr = "packages.config"
	vbprojStr         = ".vbproj"
	vcxprojStr        = ".vcxproj"
	fsprojStr         = ".fsproj"

	// PyPI file types
	requirementsTxtStr = "requirements.txt"

	pipfileStr       = "pipfile"
	pipfileLockStr   = "pipfile.lock"
	setupPyStr       = "setup.py"
	pyprojectTomlStr = "pyproject.toml"
	poetryLockStr    = "poetry.lock"
	uvLockStr        = "uv.lock"

	// add next supported manifest type string rep here
)
