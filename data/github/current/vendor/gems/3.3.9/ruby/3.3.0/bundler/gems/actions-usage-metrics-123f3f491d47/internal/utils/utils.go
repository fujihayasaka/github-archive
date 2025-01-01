package utils

import (
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func RemoveDuplicates[T comparable](sliceList []T) []T {
	allKeys := make(map[T]bool)
	list := []T{}
	for _, item := range sliceList {
		if _, value := allKeys[item]; !value {
			allKeys[item] = true
			list = append(list, item)
		}
	}
	return list
}

// Case-insensitive string contains.
func ContainsI(a string, b string) bool {
	return strings.Contains(
		strings.ToLower(a),
		strings.ToLower(b),
	)
}

func EnumsToStrings[T any](enums []T) ([]string, error) {
	strings := make([]string, len(enums))
	for i, value := range enums {
		str := fmt.Sprintf("%v", value)
		strings[i] = str
	}
	return strings, nil
}

func ChunkSlice[T any](slice []T, chunkSize int) [][]T {
	var chunks [][]T
	for i := 0; i < len(slice); i += chunkSize {
		end := i + chunkSize
		if end > len(slice) {
			end = len(slice)
		}
		chunks = append(chunks, slice[i:end])
	}
	return chunks

}

func Map[T any, R any](collection []T, iteratee func(item T, index int) R) []R {
	// example: https://go.dev/play/p/OkPcYAhBo0D
	result := make([]R, len(collection))

	for i := range collection {
		result[i] = iteratee(collection[i], i)
	}

	return result
}

func GetScopeFromOwnerId(ownerId int64) *proto.Scope {
	// temporary helper to get ownerId in scope until callers are updated

	scope := proto.Scope{
		OwnerId:   &ownerId,
		ScopeType: proto.ScopeType_SCOPE_TYPE_ORG,
	}

	return &scope
}

func GetScopeFromRepo(ownerId int64, repo int64) *proto.Scope {
	// temporary helper to get ownerId in scope until callers are updated

	scope := proto.Scope{
		OwnerId:      &ownerId,
		RepositoryId: &repo,
		ScopeType:    proto.ScopeType_SCOPE_TYPE_REPO,
	}

	return &scope
}

func GetScopeFromEnterpriseOrgs(enterpriseOrgs []int64) *proto.Scope {
	// temporary helper to get ownerId in scope until callers are updated

	scope := proto.Scope{
		EnterpriseOrgs: enterpriseOrgs,
		ScopeType:      proto.ScopeType_SCOPE_TYPE_ENTERPRISE,
	}

	return &scope
}

func SanitizeString(str string, isNumerical bool) string {
	// Check to see if sanitization needed:
	// \A  # Start at beginning of string
	// \s* # Ignore whitespace
	// =|  # = is not allowed at the beginning of an identifier
	// \+| # + is not allowed at the beginning of an identifier
	// -|  # - is not allowed at the beginning of an identifier
	// @|  # @ is not allowed at the beginning of an identifier
	// ;|  # ; is not allowed at the beginning of an identifier
	// ,|  # , is not allowed at the beginning of an identifier
	// %00 # null byte is not allowed at the beginning of an identifier
	regex := regexp.MustCompile(`\A\s*=|\+|-|@|;|,|%00`)
	match := regex.FindString(str)

	if match == "" && isNumerical {
		// no match found and is numerical so safe to return as is
		return str
	}

	// Match found so sanitize. To sanitize we do 2 things:
	// 1. Wrap Fields in Double Quotes: This helps the spreadsheet editor read the content as text.
	// 2. Escape Double Quotes: Use an additional double quote to escape each double quote in the content.
	// 3. Prepend value with single quote
	// This is based on OWASP: https://owasp.org/www-community/attacks/CSV_Injection
	regexQuote := regexp.MustCompile(`"`)
	replaced := regexQuote.ReplaceAllString(str, `""`)
	return fmt.Sprintf(`"'%s"`, replaced)
}

func IsInternalColumn(header string) bool {
	return strings.HasPrefix(header, "_")
}

func GetStartOfDay(timestamp time.Time) time.Time {
	return timestamp.Truncate(24 * time.Hour)
}
