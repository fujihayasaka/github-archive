package prompt

import (
	"bytes"
	"context"
	"embed"
	"fmt"
	"io/fs"
	"path"
	"regexp"
	"strings"
	"text/template"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/contextsset"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/snippets"
)

//go:embed templates/*.md
var embeddedTemplates embed.FS

//go:embed qhelps/*.md
var embeddedQhelps embed.FS

// numConsecutiveBackticks returns the number of consecutive backticks in the
// given string.
func numConsecutiveBackticks(x string) int {
	max := 0
	count := 0
	for i := 0; i < len(x); i++ {
		if x[i] == '`' {
			count++
		} else {
			count = 0
		}
		if count > max {
			max = count
		}
	}
	return max
}

// code wraps the given string in backticks, taking into account any backticks
// present in the string and shortening it.
//
// If the string is longer than 80 characters, it is shortened to 77 characters
// and an ellipsis is appended. If the string contains a newline, it will be
// truncated at the first newline and an ellipsis will be appended.
func code(x string) string {
	if len(x) > 80 {
		x = x[:77] + "..."
	}
	if strings.Contains(x, "\n") {
		//nolint:gocritic // the above strings.Contains(x, "\n") check ensures the index is not -1
		x = x[:strings.Index(x, "\n")] + "..."
	}
	n := numConsecutiveBackticks(x)
	if n > 0 {
		// Wrap in n + 1 backticks and a space
		delimiter := strings.Repeat("`", n+1)
		return delimiter + " " + x + " " + delimiter
	}
	return "`" + x + "`"
}

// codeBlock wraps a block of text in a Markdown style code block, taking into
// account any backticks present in the string.
func codeBlock(x string, path string) string {
	// Use the file extension as the code block language
	lang := path[strings.LastIndex(path, ".")+1:]

	n := numConsecutiveBackticks(x)
	// Wrap in n + 1 backticks, or three backticks if n < 3
	delimiter := strings.Repeat("`", max(n+1, 3))
	return delimiter + lang + "\n" + x + "\n" + delimiter
}

// MarkdownHeaderRegex is a regular expression that matches Markdown headers.
//
// note: Multi-line mode makes ^ match the start of every line, rather than just the
// start of the string.
var MarkdownHeaderRegex = regexp.MustCompile(`(?m)^#+`)

// increaseMarkdownHeaderLevels increases the level of all Markdown headers in
// the given string by the given amount.
func increaseMarkdownHeaderLevels(x string, amount int) string {
	return MarkdownHeaderRegex.ReplaceAllStringFunc(x, func(match string) string {
		return strings.Repeat("#", len(match)+amount)
	})
}

// inc increments an integer.
func inc(x int) int {
	return x + 1
}

func join(separator string, elements []string) string {
	return strings.Join(elements, separator)
}

func textWithLineNumbers(ctx context.Context) func(c contextsset.IContextsSet) (string, error) {
	return func(c contextsset.IContextsSet) (string, error) {
		// Hack to make mock context sets work
		if textWithLineNumbers, ok := c.(interface{ TextWithLineNumbers() (string, error) }); ok {
			return textWithLineNumbers.TextWithLineNumbers()
		}
		return snippets.TextWithLineNumbers(ctx, c)
	}
}

// ExecuteTemplate executes a template with the given arguments and returns
// the resulting string.
//
// templateName is the file name of a template file within the prompt package.
func ExecuteTemplate(ctx context.Context, templateName string, args interface{}) (string, error) {
	funcMap := template.FuncMap{
		"code":                         code,
		"codeBlock":                    codeBlock,
		"inc":                          inc,
		"increaseMarkdownHeaderLevels": increaseMarkdownHeaderLevels,
		"join":                         join,
		"textWithLineNumbers":          textWithLineNumbers(ctx),
	}

	t, err := template.New(templateName).Funcs(funcMap).ParseFS(embeddedTemplates, path.Join("templates", templateName))
	if err != nil {
		return "", err
	}
	var output bytes.Buffer
	err = t.Execute(&output, args)
	if err != nil {
		return "", err
	}
	return output.String(), nil
}

// FindQHelpOverride Finds the QHelp override for the given rule id.
func FindQHelpOverride(ruleID string) string {
	qhelpName := fmt.Sprintf("qhelps/%s.md", strings.ReplaceAll(ruleID, "/", "-"))
	data, err := fs.ReadFile(embeddedQhelps, qhelpName)
	if err != nil {
		// Not an error, just means no override exists
		return ""
	}

	if len(data) == 0 {
		return "" // Empty file, no override
	}

	return string(data)
}
