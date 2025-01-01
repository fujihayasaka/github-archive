package dependencies

import (
	"context"
	"fmt"

	"github.com/pkg/errors"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"
)

// IMetadataFetcher fetches metadata about a dependency from the language ecosystem
// registry (e.g. npm, PyPI, NuGet, Maven, etc.).
type IMetadataFetcher interface {
	GetMetadata(ctx context.Context, dependency string, latest bool) (fixdata.DependencyMetadata, error)
}

// IDependenciesFile is a file declaring project dependencies, in some language-specific format.
type IDependenciesFile interface {
	Contents() (string, error)
	GetCurrentDependencies() ([]string, error)
	AddDependencies(ctx context.Context, dependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error)
	GetLanguage() utils.Language
}

// IDependencySupport provides language‑specific helpers for dependency
// handling: determining whether a spec is built‑in, locating the dependency
// declaration for a given source file, and extracting a canonical dependency
// name from a raw spec provided by the model.
type IDependencySupport interface {
	IsBuiltIn(spec string) bool
	FindDependenciesFile(sourceFile codebase.File, context context.Context) IDependenciesFile
	GetDependencyName(spec string) *string
}

// FindDependenciesFile locates the dependency declaration file for the given
// source file and language (e.g. finds the nearest pom.xml for a Java file).
// Returns nil if no suitable file can be found or if required information is
// missing.
func FindDependenciesFile(
	sourceFile codebase.File,
	language utils.Language,
	context context.Context,
	addDeps AddDependenciesDeps,
) IDependenciesFile {
	if sourceFile.Path == "" {
		enhancedctx.Logger(context).Error("Empty file path provided to FindDependenciesFile")
		return nil
	}
	if sourceFile.Codebase == nil {
		enhancedctx.Logger(context).Error("Nil codebase provided to FindDependenciesFile")
		return nil
	}
	if language == "" {
		enhancedctx.Logger(context).Error("Empty language provided to FindDependenciesFile")
		return nil
	}

	logger := enhancedctx.Logger(context)
	langDepSupport, err := addDeps.GetDependencySupport(language)
	if err != nil {
		// log level is info because this is a common case.
		logger.WithError(err).Info("Failed to get dependency support: " + err.Error())
		return nil
	}

	return langDepSupport.FindDependenciesFile(sourceFile, context)
}

// AddedDependencyResult is metadata about a dependency that is added as part of a fix.
//
// This can be a successful addition, or a failure. The
// `GetAddDependencyMetadata` function can be used to discriminate between the
// two cases.
//
// Exactly one of `SuccessDependencyMetadata` and `err` is non-nil.
type AddedDependencyResult struct {
	SuccessDependencyMetadata *fixdata.DependencyMetadata
	Err                       *AddDependencyError
}

// GetAddDependencyMetadata returns the success metadata or an error for this
// added dependency attempt.
func (adr AddedDependencyResult) GetAddDependencyMetadata() (fixdata.DependencyMetadata, *AddDependencyError) {
	if adr.Err != nil {
		return fixdata.DependencyMetadata{}, adr.Err
	} else {
		return *adr.SuccessDependencyMetadata, nil
	}
}

// IsSuccess reports whether the dependency was added successfully.
func (adr AddedDependencyResult) IsSuccess() bool {
	return adr.Err == nil
}

// AddDependencyError describes a failure to add an individual dependency
// (e.g. malformed spec, metadata fetch failure, malicious package).
type AddDependencyError struct {
	reason string
}

// Error implements the error interface.
func (e AddDependencyError) Error() string {
	return e.reason
}

func allUnsuccessful(dependencies []string, reason string) AddedDependencies {
	info := map[string]AddedDependencyResult{}
	for _, dep := range dependencies {
		info[dep] = AddedDependencyResult{
			SuccessDependencyMetadata: nil,
			Err:                       &AddDependencyError{reason: reason},
		}
	}

	return AddedDependencies{
		Edits: []editcommands.FileEdit{},
		Info:  info,
	}
}

// AddDependenciesDeps is a struct that contains the dependencies needed to run
// the various functions that are part of the autofix feature to add new
// dependencies to a code base as part of the fix.
//
// We use this struct to explicitly pass the dependencies to the function, so
// that we can easily mock them in tests - it's a simple implementation of the
// dependency injection pattern.
type AddDependenciesDeps struct {
	GetDependencySupport func(utils.Language) (IDependencySupport, error)
	MetadataFetcher      func(utils.Language) IMetadataFetcher
}

// MkAddDependenciesDeps constructs the default dependency helpers used by the
// autofix dependency addition flow. It wires language support and metadata
// fetchers for all currently supported languages.
func MkAddDependenciesDeps() AddDependenciesDeps {
	return AddDependenciesDeps{
		GetDependencySupport: func(lang utils.Language) (IDependencySupport, error) {
			if lang == "" {
				return nil, errors.New("no dependency support for undefined language")
			}

			// kaeluka: this logic is risky - when adding support for a new language,
			// we have no static check that would ensure that we also add a case here.
			// Adding a case here is very easy to forget. Do we have a strategy for
			// catching this problem here and elsewhere?
			switch lang {
			case utils.LanguageCsharp:
				return NewDependencySupportCSharp(), nil
			case utils.LanguagePython:
				return NewDependencySupportPython(), nil
			case utils.LanguageJavascript:
				return NewDependencySupportJavascript(), nil
			case utils.LanguageJava:
				return NewDependencySupportJava(), nil
			case utils.LanguageGo:
				return NewDependencySupportGo(), nil
			case utils.LanguageRuby:
				return NewDependencySupportRuby(), nil
			case utils.LanguageRust:
				return NewDependencySupportRust(), nil
			default:
				return nil, errors.New("dependency support for lang '" + string(lang) + "' not yet implemented")
			}
		},
		MetadataFetcher: func(lang utils.Language) IMetadataFetcher {
			if lang == "" {
				return nil
			}

			// kaeluka: this logic is risky - when adding support for a new language,
			// we have no static check that would ensure that we also add a case here.
			// Adding a case here is very easy to forget. Do we have a strategy for
			// catching this problem here and elsewhere?
			switch lang {
			case utils.LanguageCsharp:
				return NugetMetadataFetcher{}
			case utils.LanguagePython:
				return PyPIMetadataFetcher{}
			case utils.LanguageJavascript:
				return NpmMetadataFetcher{}
			case utils.LanguageJava:
				return NewMavenMetadataFetcher()
			case utils.LanguageGo:
				return NewGoPackagesMetadataFetcher()
			case utils.LanguageRuby:
				return NewRubyGemsMetadataFetcher()
			case utils.LanguageRust:
				return NewCrateMetadataFetcher()
			default:
				return nil
			}
		},
	}
}

// CreateAddDependenciesEditCommands creates edit commands to add dependencies to a code base.
func CreateAddDependenciesEditCommands(
	ctx context.Context,
	file codebase.File,
	language utils.Language,
	dependencies []string,
	addDeps AddDependenciesDeps,
) (result AddedDependencies) {
	defer func() {
		if r := recover(); r != nil {
			enhancedctx.Logger(ctx).Error("Panic in CreateAddDependenciesEditCommands",
				kvp.Any("recover", r))
			result = allUnsuccessful(dependencies, fmt.Sprintf("internal error: %v", r))
		}
	}()

	if ctx == nil {
		return allUnsuccessful(dependencies, "nil context provided")
	}

	if ctx.Err() != nil {
		return allUnsuccessful(dependencies, "context cancelled: "+ctx.Err().Error())
	}

	enhancedctx.Logger(ctx).WithFields(
		kvp.String("language", string(language)),
		kvp.Int("dependencies_count", len(dependencies)),
		kvp.String("file_path", file.Path),
	).Debug("Processing dependencies")

	if language == "" {
		return allUnsuccessful(dependencies, "no language specified")
	}

	// filter out built-in dependencies
	langDepSupport, err := addDeps.GetDependencySupport(language)
	if err != nil {
		return allUnsuccessful(dependencies, "failed to get dependency support: "+err.Error())
	}

	filtered := make([]string, 0, len(dependencies))
	for _, dep := range dependencies {
		if dep == "" {
			continue // Skips empty dependencies
		}
		if !langDepSupport.IsBuiltIn(dep) {
			filtered = append(filtered, dep)
		}
	}
	dependencies = filtered

	if len(dependencies) == 0 {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  map[string]AddedDependencyResult{},
		}
	}

	depsFile := FindDependenciesFile(file, language, ctx, addDeps)
	if depsFile == nil {
		enhancedctx.Logger(ctx).Error("No dependencies file found")
		return allUnsuccessful(dependencies, "no dependencies file found")
	}

	ret, err := depsFile.AddDependencies(ctx, dependencies, addDeps)
	if err != nil {
		enhancedctx.Logger(ctx).WithError(err).Error("Error adding dependencies")
		return allUnsuccessful(dependencies, err.Error())
	}

	enhancedctx.Logger(ctx).Info("Successfully added dependencies")
	return ret
}
