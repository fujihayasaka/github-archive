package sarif

import (
	"strings"

	"github.com/github/turboscan/ts"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/pkg/errors"
)

// notificationExistsExtensionsOrDriver returns whether a given notication with notification.Descriptor.Id
// exists in the given collection of notifications with tags or given collection of extension notifications with tags.
//
// The lookup follows the SARIF spec (§3.54.2)
// If neither `index` (§3.54.4) nor `guid` (§3.54.5) is present, theComponent SHALL be `Tool.Driver` (§3.18.2).
// If `index` is present, theComponent SHALL be the object at array index index within `Tool.Extensions` (§3.18.3).
// If index is absent and guid is present, theComponent SHALL be either `Tool.Driver` or an element
// of `Tool.extensions`, whichever one has a matching guid property.
//
// NOTE: currently CodeQL doesn't produce ToolComponent with `guid` property therefore that branch has not been implemented.
func notificationExistsExtensionsOrDriver(notification *v2_1_0.Notification, driverNotifications []*v2_1_0.ReportingDescriptor, extensionsNotificationsList [][]*v2_1_0.ReportingDescriptor) bool {
	if notification == nil {
		return false
	}
	if notification.Descriptor == nil {
		return false
	}
	if notification.Descriptor.ToolComponent != nil && notification.Descriptor.ToolComponent.Index > -1 {
		if notification.Descriptor.ToolComponent.Index >= len(extensionsNotificationsList) {
			return false
		}
		return notificationLookup(notification, extensionsNotificationsList[notification.Descriptor.ToolComponent.Index])
	}
	return notificationLookup(notification, driverNotifications)
}

func notificationLookup(notification *v2_1_0.Notification, items []*v2_1_0.ReportingDescriptor) bool {
	for _, item := range items {
		if notification.Descriptor.Id == item.Id {
			return true
		}
	}
	return false
}

// See normalizeLanguage
var langMap = map[string]string{
	"javascript": "js",
	"js":         "js",
	"csharp":     "cs",
	"cs":         "cs",
	"python":     "py",
	"py":         "py",
	"ruby":       "rb",
	"rb":         "rb",
}

// siblingLanguage returns the sibling language of the given language.
// Two languages are siblings if they are both sublanguages for the same language.
// Note that the spelling of the language names is case-sensitive, and is the
// one used by CodeQL in the `languageDisplayName` property of the SARIF file.
func siblingLanguage(in string) string {
	switch in {
	case "Java":
		return "Kotlin"
	case "Kotlin":
		return "Java"
	case "JavaScript":
		return "TypeScript"
	case "TypeScript":
		return "JavaScript"
	case "C":
		return "C++"
	case "C++":
		return "C"
	default:
		return in
	}
}

// Maps language identifiers from CodeQL to a canonical language identifier.
//
// This is a workaround to handle the fact that CodeQL version 2.11.3 and earlier uses different identifiers for
// languages to later versions of CodeQL. Mapping these to canonical identifiers simplifies things downstream.
//
// This can be removed once support for CodeQL v2.11.3 is deprecated (estimated March 2024).
func normalizeLanguage(l string) string {
	lang, ok := langMap[l]
	if !ok {
		return l
	}
	return lang
}

// getLanguageFromReportingDescriptor returns the language name from the reporting descriptor.
//
// This may be a display name, like "JavaScript", or a canonical language identifier, like "js",
// depending on the CodeQL version that submitted the SARIF.
//
// This can be removed once all supported CodeQL versions populate the `languageDisplayName`
// property, i.e. once the CodeQL v2.14.* series reaches end of life.
func getLanguageFromReportingDescriptor(descriptor *v2_1_0.ReportingDescriptor) string {
	if descriptor.Properties != nil && descriptor.Properties.LanguageDisplayName != "" {
		return descriptor.Properties.LanguageDisplayName
	}
	idx := strings.IndexByte(descriptor.Id, '/')
	if idx < 0 {
		idx = len(descriptor.Id)
	}
	return normalizeLanguage(descriptor.Id[:idx])
}

// getNotificationsWithTag looks up notifications with the given tag in the provided SARIF run.
//
// It returns a list of notifications from the driver, a list containing lists of notifications for
// each extension, and a boolean for convenience indicating whether any notifications were found.
func getNotificationsWithTag(run *v2_1_0.Run, tag v2_1_0.Tag) ([]*v2_1_0.ReportingDescriptor, [][]*v2_1_0.ReportingDescriptor, bool) {
	driverNotifications := run.Tool.Driver.NotificationsWithTag(tag)
	found := len(driverNotifications) > 0
	extensionsNotificationsList := make([][]*v2_1_0.ReportingDescriptor, 0, len(run.Tool.Extensions))
	for _, extension := range run.Tool.Extensions {
		extensionNotifications := extension.NotificationsWithTag(tag)
		extensionsNotificationsList = append(extensionsNotificationsList, extensionNotifications)
		if len(extensionNotifications) > 0 {
			found = true
		}
	}

	return driverNotifications, extensionsNotificationsList, found
}

// getFilesFromRunWithTag returns a FileSet with all the files with rule that are tagged as v2_1_0.Tag
func getFilesFromRunWithTag(run *v2_1_0.Run, tag v2_1_0.Tag) (map[string]ts.FileSet, error) {
	out := map[string]ts.FileSet{}
	driverNotifications, extensionsNotificationsList, found := getNotificationsWithTag(run, tag)

	if !found {
		return nil, nil
	}

	// store the languages even if we didn't match any files so that we can use the labels when displaying
	// information on the tool status page and for determining if there were any analyzable files
	for _, notifications := range append(extensionsNotificationsList, driverNotifications) {
		for _, notification := range notifications {
			language := getLanguageFromReportingDescriptor(notification)

			if _, ok := out[language]; !ok {
				out[language] = ts.FileSet{}
			}
		}
	}

	for _, invocation := range run.Invocations {
		workingDirectory := ts.EmptyCheckoutURI
		if invocation.WorkingDirectory != nil {
			workingDirectory = ts.ToCheckoutURI(invocation.WorkingDirectory.Uri)
		}
		for _, notification := range invocation.ToolExecutionNotifications {
			if notificationExistsExtensionsOrDriver(notification, driverNotifications, extensionsNotificationsList) {
				_, reportingDescriptor, err := run.LookupNotification(notification)
				if err != nil {
					return nil, errors.Wrap(err, "could not find reporting descriptor for notification")
				}
				language := getLanguageFromReportingDescriptor(reportingDescriptor)

				if _, ok := out[language]; !ok {
					out[language] = ts.FileSet{}
				}

				locations := notification.Locations
				if len(locations) == 0 {
					continue
				}
				physicalLocation := locations[0].PhysicalLocation
				if physicalLocation == nil {
					continue
				}
				artifactLocation := physicalLocation.ArtifactLocation
				if artifactLocation == nil || artifactLocation.Uri == "" {
					continue
				}
				path, err := URIToPath(artifactLocation.Uri, workingDirectory)
				if err != nil {
					return nil, errors.Wrap(err, "could not extract path from notification")
				}
				out[language][path] = struct{}{}
			}
		}
	}
	return out, nil
}

// GetSuccessfullyExtractedFiles returns a FileSet of all files with rule that have a tag `v2_1_0.SuccessfullyExtracted`.
func GetSuccessfullyExtractedFiles(run *v2_1_0.Run) (map[string]ts.FileSet, error) {
	return getFilesFromRunWithTag(run, v2_1_0.SuccessfullyExtracted)
}

// GetBaselineExtractedFiles returns a FileSet of all files with rule that have a tag `v2_1_0.BaselineExtracted`.
func GetBaselineExtractedFiles(run *v2_1_0.Run) (map[string]ts.FileSet, error) {
	return getFilesFromRunWithTag(run, v2_1_0.BaselineExtracted)
}

func isSublanguageFileCoverageEnabled(run *v2_1_0.Run) bool {
	driverNotifications, extensionsNotificationsList, _ := getNotificationsWithTag(run, v2_1_0.BaselineExtracted)

	for _, notifications := range append(extensionsNotificationsList, driverNotifications) {
		for _, notification := range notifications {
			if !strings.HasPrefix(notification.Id, "cli/") {
				return false
			}
		}
	}

	return true
}

// GetExtractedFiles returns a FileSet of all extracted files.
//
// The set of extracted files is computed differently depending on whether the SARIF file contains
// sub-language file coverage information.
//
//   - When sub-language file coverage information is enabled, the set of extracted files is the set
//     of successfully extracted files (see GetSuccessfullyExtractedFiles) that appear in the
//     baseline. The key of the returned map is the language display name, as it appears in the
//     baseline.
//
//   - When sub-language file coverage information is disabled, the set of extracted files is the
//     set of all successfully extracted files (see GetSuccessfullyExtractedFiles). The key of the
//     returned map is the language identifier from the successfully extracted files reporting
//     descriptor.
func GetExtractedFiles(run *v2_1_0.Run, baselineByLanguage map[string]ts.FileSet) (map[string]ts.FileSet, error) {
	successful, err := GetSuccessfullyExtractedFiles(run)
	if err != nil {
		return nil, err
	}

	if isSublanguageFileCoverageEnabled(run) {
		if baselineByLanguage == nil {
			return nil, nil
		}
		allSuccessfulFiles := make(ts.FileSet)
		for lang := range successful {
			allSuccessfulFiles = allSuccessfulFiles.Union(successful[lang])
		}

		extractedFilesAll := make(map[string]ts.FileSet)
		for lang := range baselineByLanguage {
			extractedFilesAll[lang] = allSuccessfulFiles.Intersection(baselineByLanguage[lang])
		}
		// Only report extracted files for languages that have at least one successfully
		// extracted file for a sublanguage.
		// This is to save space in the DB in the common case for code scanning
		// where we are analyzing one language per analysis configuration / category. In this
		// case, we only want to store the file coverage information for the language being
		// analyzed. We account for sublanguages so that reporting for (e.g.) `java-kotlin`
		// correctly reports both Java and Kotlin.
		//
		// It's useful for customers to know what languages exist in their repo that they aren't
		// currently analyzing, but before we get there we probably want to be storing file
		// coverage information per repo rather than per analysis configuration / category to
		// avoid storing so much in the DB.
		extractedFiles := make(map[string]ts.FileSet)
		for lang, extractedFilesForLang := range extractedFilesAll {
			if len(extractedFilesForLang) != 0 || len(extractedFilesAll[siblingLanguage(lang)]) != 0 {
				extractedFiles[lang] = extractedFilesForLang
			}
		}
		return extractedFiles, nil
	} else {
		return successful, nil
	}
}

// GetNotExtractedFiles returns the set of BaselineExtractedFiles with the successfully extracted paths removed.
func GetNotExtractedFiles(baselineByLanguage map[string]ts.FileSet, allSuccessfulFiles ts.FileSet) map[string]ts.FileSet {
	// if baselineByLanguage is nil then it wasn't included in the sarif document
	if baselineByLanguage == nil {
		return nil
	}

	notExtractedFilesAll := make(map[string]ts.FileSet)
	for lang := range baselineByLanguage {
		notExtractedFilesAll[lang] = baselineByLanguage[lang].Diff(allSuccessfulFiles)
	}
	// Only store not extracted information for languages that have at least one extracted file
	// to save space in the DB. See the corresponding comment in `GetExtractedFiles` for more
	// context.
	notExtractedFiles := make(map[string]ts.FileSet)
	for lang, notExtractedFilesForLang := range notExtractedFilesAll {
		siblingLang := siblingLanguage(lang)
		if len(notExtractedFilesForLang) < len(baselineByLanguage[lang]) || len(notExtractedFilesAll[siblingLang]) < len(baselineByLanguage[siblingLang]) {
			notExtractedFiles[lang] = notExtractedFilesForLang
		}
	}
	return notExtractedFiles
}

// GetCodeQLExtractorErrors maps file paths in the SARIF's toolExecutionNotifications to Notification with highest severity level
func GetCodeQLExtractorErrors(notification *v2_1_0.Notification, workingDirectory ts.CheckoutURI, toolErrors map[string]*v2_1_0.Notification, notExtractedFiles ts.FileSet) error {
	if notification.Level == "none" || notification.Level == "note" {
		return nil
	}
	if notification.Message != nil && notification.Message.Text == "" {
		return nil
	}

	for _, location := range notification.Locations {
		pl := location.PhysicalLocation
		if pl == nil || pl.ArtifactLocation == nil {
			continue
		}

		path, err := URIToPath(pl.ArtifactLocation.Uri, workingDirectory)
		if err != nil {
			return errors.Wrap(err, "could not extract path from notification")
		}
		if notExtractedFiles.Contains(path) {
			if _, exists := toolErrors[path]; !exists || notification.Level == "error" {
				toolErrors[path] = notification
			}
		}
	}

	return nil
}
