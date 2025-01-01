package sarif_test

import (
	"os"
	"reflect"
	"testing"

	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	v210turboscan "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
)

// TODO: Add logic + tests for Severity

func loadTestDefaultsAugmentor(filename string) (sarif.RuleMetadataAugmentor, error) {
	b, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	return sarif.NewRuleMetadataAugmentor([][]byte{b})
}

func TestExpectedToolsHaveDefaults(t *testing.T) {
	rma, err := sarif.DefaultRuleMetadataAugmentor()
	require.NoError(t, err)
	tools, err := rma.ToolsWithDefaultRuleData()
	require.NoError(t, err)
	require.Equal(t, 3, len(tools))
	require.Contains(t, tools, "CodeQL")
	require.Contains(t, tools, "Rubocop")
	require.Contains(t, tools, "ESLint")
}

func TestDeletedRulesHaveDefaults(t *testing.T) {
	rma, err := sarif.DefaultRuleMetadataAugmentor()
	require.NoError(t, err)
	run := &v210turboscan.Run{
		Tool: &v210turboscan.Tool{
			Driver: &v210turboscan.ToolComponent{
				Name: "CodeQL",
				Rules: []*v210turboscan.Rule{
					{Id: "cpp/file-never-closed"},
					{Id: "cpp/sql-injection-via-pqxx"},
				},
			},
		},
	}
	require.NoError(t, rma.AugmentDefaultRuleData(run))
	// from codeql.sarif
	require.Equal(t, "cpp/file-never-closed", run.Tool.Driver.Rules[0].Id)
	require.Equal(t, "Open file is not closed", run.Tool.Driver.Rules[0].ShortDescription.Text)
	// from codeql-deleted.sarif
	require.Equal(t, "cpp/sql-injection-via-pqxx", run.Tool.Driver.Rules[1].Id)
	require.Equal(t, "Uncontrolled data in SQL query to Postgres", run.Tool.Driver.Rules[1].ShortDescription.Text)
}

func TestWellKnownRuleIsAugmented(t *testing.T) {
	rma, err := loadTestDefaultsAugmentor("testdata/nometadata_defaults.sarif")
	require.NoError(t, err)

	s := samples.RequireSARIF(t, "testdata/nometadata.sarif")

	rule := s.Runs[0].Tool.Driver.Rules[0]

	// Verify input data
	require.Equal(t, "js/unused-local-variable", rule.Id)
	require.Equal(t, "", rule.DefaultConfiguration.Level)
	require.Equal(t, "", rule.FullDescription.Text)
	require.Equal(t, "", rule.FullDescription.Markdown)
	require.Nil(t, rule.Help)
	require.Equal(t, "", rule.HelpUri)
	require.Equal(t, "", rule.Name)
	require.Equal(t, "", rule.Properties.Precision)
	require.Equal(t, "", rule.Properties.QueryURI)
	require.Equal(t, "", rule.Properties.SecuritySeverity)
	require.Nil(t, rule.Properties.Tags)
	require.Nil(t, rule.ShortDescription)

	err = rma.AugmentDefaultRuleData(s.Runs[0])
	require.NoError(t, err)

	rule = s.Runs[0].Tool.Driver.Rules[0]

	// Verify data after augmentation
	require.Equal(t, "js/unused-local-variable", rule.Id)

	// Fields that were missing are now filled in
	require.Equal(t, "note", rule.DefaultConfiguration.Level)
	require.Equal(t, "Unused variables, imports, functions or classes may be a symptom of a bug and should be examined carefully.", rule.FullDescription.Text)
	require.Equal(t, "test full description markdown", rule.FullDescription.Markdown)
	require.Equal(t, "# Unused variable, import, function or class\nUnused local variables make code hard to read and understand. Any computation used to initialize an unused variable is wasted, which may lead to performance problems.\n\nSimilarly, unused imports and unused functions or classes can be confusing. They may even be a symptom of a bug caused, for example, by an incomplete refactoring.\n\n\n## Recommendation\nRemove the unused program element.\n\n\n## Example\nIn this code, the function `f` initializes a local variable `x` with a call to the function `expensiveComputation`, but later on this variable is never read. Removing `x` would improve code quality and performance.\n\n\n```javascript\nfunction f() {\n\tvar x = expensiveComputation();\n\treturn 23;\n}\n```\nA slightly subtle case is shown below, where a function expression named `f` is assigned to a variable `f`:\n\n\n```javascript\nvar f = function f() {\n  return \"Hi!\";\n};\nf();\n```\nNote that this example involves two distinct variables, both named `f`: the global variable to which the function is assigned, and the variable implicitly declared by the function expression. The call to `f()` refers to the former variable, whereas the latter is unused. Hence the example can be rewritten as follows, eliminating the useless variable:\n\n\n```javascript\nvar f = function () {\n  return \"Hi!\";\n};\nf();\n```\nA similar situation can occur with ECMAScript 2015 module exports, as shown in the following example:\n\n\n```javascript\nexport default function f() {\n  return \"Hi!\";\n};\n```\nAgain, the named function expression implicitly declares a variable `f`, but because the export statement is a default export, this variable is unused and can be eliminated:\n\n\n```javascript\nexport default function () {\n  return \"Hi!\";\n};\n```\n\n## References\n* Coding Horror: [Code Smells](http://blog.codinghorror.com/code-smells/).\n* Mozilla Developer Network: [Named function expressions](https://developer.mozilla.org/en/docs/web/JavaScript/Reference/Operators/function#Named_function_expression).\n* Mozilla Developer Network: [Using the default export](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/export#Using_the_default_export).\n", rule.Help.Text)
	require.Equal(t, "# Unused variable, import, function or class\nUnused local variables make code hard to read and understand. Any computation used to initialize an unused variable is wasted, which may lead to performance problems.\n\nSimilarly, unused imports and unused functions or classes can be confusing. They may even be a symptom of a bug caused, for example, by an incomplete refactoring.\n\n\n## Recommendation\nRemove the unused program element.\n\n\n## Example\nIn this code, the function `f` initializes a local variable `x` with a call to the function `expensiveComputation`, but later on this variable is never read. Removing `x` would improve code quality and performance.\n\n\n```javascript\nfunction f() {\n\tvar x = expensiveComputation();\n\treturn 23;\n}\n```\nA slightly subtle case is shown below, where a function expression named `f` is assigned to a variable `f`:\n\n\n```javascript\nvar f = function f() {\n  return \"Hi!\";\n};\nf();\n```\nNote that this example involves two distinct variables, both named `f`: the global variable to which the function is assigned, and the variable implicitly declared by the function expression. The call to `f()` refers to the former variable, whereas the latter is unused. Hence the example can be rewritten as follows, eliminating the useless variable:\n\n\n```javascript\nvar f = function () {\n  return \"Hi!\";\n};\nf();\n```\nA similar situation can occur with ECMAScript 2015 module exports, as shown in the following example:\n\n\n```javascript\nexport default function f() {\n  return \"Hi!\";\n};\n```\nAgain, the named function expression implicitly declares a variable `f`, but because the export statement is a default export, this variable is unused and can be eliminated:\n\n\n```javascript\nexport default function () {\n  return \"Hi!\";\n};\n```\n\n## References\n* Coding Horror: [Code Smells](http://blog.codinghorror.com/code-smells/).\n* Mozilla Developer Network: [Named function expressions](https://developer.mozilla.org/en/docs/web/JavaScript/Reference/Operators/function#Named_function_expression).\n* Mozilla Developer Network: [Using the default export](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/export#Using_the_default_export).\n", rule.Help.Markdown)
	require.Equal(t, "https://www.example.com", rule.HelpUri)
	require.Equal(t, "js/unused-local-variable", rule.Name)
	require.Equal(t, "very-high", rule.Properties.Precision)
	require.Equal(t, "https://github.com/github/codeql/tree/main/javascript/ql/src/Declarations/UnusedVariable.ql", rule.Properties.QueryURI)
	require.Equal(t, "test secure severe", rule.Properties.SecuritySeverity)
	require.Equal(t, []string{"maintainability"}, rule.Properties.Tags)
	require.Equal(t, "test short description markdown", rule.ShortDescription.Markdown)
	require.Equal(t, "Unused variable, import, function or class", rule.ShortDescription.Text)
}

func TestExistingDataIsRetained(t *testing.T) {
	rma, err := loadTestDefaultsAugmentor("testdata/nometadata_defaults.sarif")
	require.NoError(t, err)

	s := samples.RequireSARIF(t, "testdata/nometadata.sarif")

	rule := s.Runs[0].Tool.Driver.Rules[0]

	// Verify input data
	require.Equal(t, "js/unused-local-variable", rule.Id)
	require.Equal(t, "", rule.FullDescription.Text)
	require.Equal(t, "", rule.FullDescription.Markdown)
	require.Nil(t, rule.Help)
	require.Equal(t, "", rule.HelpUri)
	require.Equal(t, "", rule.Name)
	require.Nil(t, rule.ShortDescription)

	// set some data
	rule.FullDescription.Text = "test full description text"
	rule.Help = &v210turboscan.MultiformatMessageString{
		Text:     "test help text",
		Markdown: "test help markdown",
	}
	rule.Name = "test name"

	err = rma.AugmentDefaultRuleData(s.Runs[0])
	require.NoError(t, err)

	rule = s.Runs[0].Tool.Driver.Rules[0]

	// Verify data after augmentation
	require.Equal(t, "js/unused-local-variable", rule.Id)

	// Fields that were present are retained
	require.Equal(t, "test full description text", rule.FullDescription.Text)
	require.Equal(t, "test help text", rule.Help.Text)
	require.Equal(t, "test help markdown", rule.Help.Markdown)
	require.Equal(t, "test name", rule.Name)

	// Fields that were missing are now filled in
	require.Equal(t, "note", rule.DefaultConfiguration.Level)
	require.Equal(t, "https://www.example.com", rule.HelpUri)
	require.Equal(t, "test short description markdown", rule.ShortDescription.Markdown)
	require.Equal(t, "Unused variable, import, function or class", rule.ShortDescription.Text)
}

func TestWellKnownRuleIsAugmentedExt(t *testing.T) {
	rma, err := loadTestDefaultsAugmentor("testdata/nometadata_defaults.sarif")
	require.NoError(t, err)

	s := samples.RequireSARIF(t, "testdata/nometadataExtensions.sarif")

	rule := s.Runs[0].Tool.Extensions[0].Rules[0]

	// Verify input data
	require.Equal(t, "js/unused-local-variable", rule.Id)
	require.Equal(t, "", rule.DefaultConfiguration.Level)
	require.Equal(t, "", rule.FullDescription.Text)
	require.Equal(t, "", rule.FullDescription.Markdown)
	require.Nil(t, rule.Help)
	require.Equal(t, "", rule.HelpUri)
	require.Equal(t, "", rule.Name)
	require.Equal(t, "", rule.Properties.Precision)
	require.Equal(t, "", rule.Properties.QueryURI)
	require.Equal(t, "", rule.Properties.SecuritySeverity)
	require.Nil(t, rule.Properties.Tags)
	require.Nil(t, rule.ShortDescription)

	err = rma.AugmentDefaultRuleData(s.Runs[0])
	require.NoError(t, err)

	rule = s.Runs[0].Tool.Extensions[0].Rules[0]

	// Verify data after augmentation
	require.Equal(t, "js/unused-local-variable", rule.Id)

	// Fields that were missing are now filled in
	require.Equal(t, "note", rule.DefaultConfiguration.Level)
	require.Equal(t, "Unused variables, imports, functions or classes may be a symptom of a bug and should be examined carefully.", rule.FullDescription.Text)
	require.Equal(t, "test full description markdown", rule.FullDescription.Markdown)
	require.Equal(t, "# Unused variable, import, function or class\nUnused local variables make code hard to read and understand. Any computation used to initialize an unused variable is wasted, which may lead to performance problems.\n\nSimilarly, unused imports and unused functions or classes can be confusing. They may even be a symptom of a bug caused, for example, by an incomplete refactoring.\n\n\n## Recommendation\nRemove the unused program element.\n\n\n## Example\nIn this code, the function `f` initializes a local variable `x` with a call to the function `expensiveComputation`, but later on this variable is never read. Removing `x` would improve code quality and performance.\n\n\n```javascript\nfunction f() {\n\tvar x = expensiveComputation();\n\treturn 23;\n}\n```\nA slightly subtle case is shown below, where a function expression named `f` is assigned to a variable `f`:\n\n\n```javascript\nvar f = function f() {\n  return \"Hi!\";\n};\nf();\n```\nNote that this example involves two distinct variables, both named `f`: the global variable to which the function is assigned, and the variable implicitly declared by the function expression. The call to `f()` refers to the former variable, whereas the latter is unused. Hence the example can be rewritten as follows, eliminating the useless variable:\n\n\n```javascript\nvar f = function () {\n  return \"Hi!\";\n};\nf();\n```\nA similar situation can occur with ECMAScript 2015 module exports, as shown in the following example:\n\n\n```javascript\nexport default function f() {\n  return \"Hi!\";\n};\n```\nAgain, the named function expression implicitly declares a variable `f`, but because the export statement is a default export, this variable is unused and can be eliminated:\n\n\n```javascript\nexport default function () {\n  return \"Hi!\";\n};\n```\n\n## References\n* Coding Horror: [Code Smells](http://blog.codinghorror.com/code-smells/).\n* Mozilla Developer Network: [Named function expressions](https://developer.mozilla.org/en/docs/web/JavaScript/Reference/Operators/function#Named_function_expression).\n* Mozilla Developer Network: [Using the default export](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/export#Using_the_default_export).\n", rule.Help.Text)
	require.Equal(t, "# Unused variable, import, function or class\nUnused local variables make code hard to read and understand. Any computation used to initialize an unused variable is wasted, which may lead to performance problems.\n\nSimilarly, unused imports and unused functions or classes can be confusing. They may even be a symptom of a bug caused, for example, by an incomplete refactoring.\n\n\n## Recommendation\nRemove the unused program element.\n\n\n## Example\nIn this code, the function `f` initializes a local variable `x` with a call to the function `expensiveComputation`, but later on this variable is never read. Removing `x` would improve code quality and performance.\n\n\n```javascript\nfunction f() {\n\tvar x = expensiveComputation();\n\treturn 23;\n}\n```\nA slightly subtle case is shown below, where a function expression named `f` is assigned to a variable `f`:\n\n\n```javascript\nvar f = function f() {\n  return \"Hi!\";\n};\nf();\n```\nNote that this example involves two distinct variables, both named `f`: the global variable to which the function is assigned, and the variable implicitly declared by the function expression. The call to `f()` refers to the former variable, whereas the latter is unused. Hence the example can be rewritten as follows, eliminating the useless variable:\n\n\n```javascript\nvar f = function () {\n  return \"Hi!\";\n};\nf();\n```\nA similar situation can occur with ECMAScript 2015 module exports, as shown in the following example:\n\n\n```javascript\nexport default function f() {\n  return \"Hi!\";\n};\n```\nAgain, the named function expression implicitly declares a variable `f`, but because the export statement is a default export, this variable is unused and can be eliminated:\n\n\n```javascript\nexport default function () {\n  return \"Hi!\";\n};\n```\n\n## References\n* Coding Horror: [Code Smells](http://blog.codinghorror.com/code-smells/).\n* Mozilla Developer Network: [Named function expressions](https://developer.mozilla.org/en/docs/web/JavaScript/Reference/Operators/function#Named_function_expression).\n* Mozilla Developer Network: [Using the default export](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/export#Using_the_default_export).\n", rule.Help.Markdown)
	require.Equal(t, "https://www.example.com", rule.HelpUri)
	require.Equal(t, "js/unused-local-variable", rule.Name)
	require.Equal(t, "very-high", rule.Properties.Precision)
	require.Equal(t, "https://github.com/github/codeql/tree/main/javascript/ql/src/Declarations/UnusedVariable.ql", rule.Properties.QueryURI)
	require.Equal(t, "test secure severe", rule.Properties.SecuritySeverity)
	require.Equal(t, []string{"maintainability"}, rule.Properties.Tags)
	require.Equal(t, "test short description markdown", rule.ShortDescription.Markdown)
	require.Equal(t, "Unused variable, import, function or class", rule.ShortDescription.Text)
}

func TestExistingDataIsRetainedExt(t *testing.T) {
	rma, err := loadTestDefaultsAugmentor("testdata/nometadata_defaults.sarif")
	require.NoError(t, err)

	s := samples.RequireSARIF(t, "testdata/nometadataExtensions.sarif")

	rule := s.Runs[0].Tool.Extensions[0].Rules[0]

	// Verify input data
	require.Equal(t, "js/unused-local-variable", rule.Id)
	require.Equal(t, "", rule.FullDescription.Text)
	require.Equal(t, "", rule.FullDescription.Markdown)
	require.Nil(t, rule.Help)
	require.Equal(t, "", rule.HelpUri)
	require.Equal(t, "", rule.Name)
	require.Nil(t, rule.ShortDescription)

	// set some data
	rule.FullDescription.Text = "test full description text"
	rule.Help = &v210turboscan.MultiformatMessageString{
		Text:     "test help text",
		Markdown: "test help markdown",
	}
	rule.Name = "test name"

	err = rma.AugmentDefaultRuleData(s.Runs[0])
	require.NoError(t, err)

	rule = s.Runs[0].Tool.Extensions[0].Rules[0]

	// Verify data after augmentation
	require.Equal(t, "js/unused-local-variable", rule.Id)

	// Fields that were present are retained
	require.Equal(t, "test full description text", rule.FullDescription.Text)
	require.Equal(t, "test help text", rule.Help.Text)
	require.Equal(t, "test help markdown", rule.Help.Markdown)
	require.Equal(t, "test name", rule.Name)

	// Fields that were missing are now filled in
	require.Equal(t, "note", rule.DefaultConfiguration.Level)
	require.Equal(t, "https://www.example.com", rule.HelpUri)
	require.Equal(t, "test short description markdown", rule.ShortDescription.Markdown)
	require.Equal(t, "Unused variable, import, function or class", rule.ShortDescription.Text)
}

// We use reflection to assert that all fields of ReportingDescriptor are covered in augmentRule
func TestAugmentationCoversAllFields(t *testing.T) {
	// This is the list of fields we know we cover (or have deliberately decided to not cover) in augmentRule.
	// It is supposed to be updated manually and kept in sync with the code.
	knownFields := []string{
		"DefaultConfiguration",
		"DefaultConfiguration.Level",
		"FullDescription",
		"FullDescription.Markdown",
		"FullDescription.Text",
		"ShortDescription",
		"ShortDescription.Markdown",
		"ShortDescription.Text",
		"Help",
		"Help.Markdown",
		"Help.Text",
		"HelpUri",
		"Id",
		"Name",
		"Properties",
		"Properties.LanguageDisplayName",
		"Properties.Precision",
		"Properties.QueryURI",
		"Properties.SecuritySeverity",
		"Properties.Tags",
	}

	rd := v210turboscan.ReportingDescriptor{}
	rdType := reflect.TypeOf(rd)
	checks := helpTestAugmentationCoversAllFields(t, knownFields, "", rdType)
	require.Equal(t, len(knownFields), checks)
}

func helpTestAugmentationCoversAllFields(t *testing.T, knownFields []string, prefix string, typ reflect.Type) int {
	t.Helper()
	// count how many checks we do
	count := 0
	// Inspect all fields
	for i := 0; i < typ.NumField(); i++ {
		field := typ.Field(i)
		s := prefix + field.Name
		require.Contains(t, knownFields, s)
		count++

		// Check if we need to recurse
		recType := field.Type
		if recType.Kind() == reflect.Ptr {
			recType = recType.Elem()
		}
		if recType.Kind() == reflect.Struct {
			// For fields of type struct, recurse
			count += helpTestAugmentationCoversAllFields(t, knownFields, s+".", recType)
		}
	}

	return count
}

func TestErrorOnDuplicatedRuleId(t *testing.T) {
	b, err := os.ReadFile("ruledata/codeql.sarif")
	require.NoError(t, err)

	// no error initially
	_, err = sarif.NewRuleMetadataAugmentor([][]byte{b})
	require.NoError(t, err)

	// but do error when we add the same data twice
	_, err = sarif.NewRuleMetadataAugmentor([][]byte{b, b})
	require.Error(t, err)

	// and no error when loading defaults
	_, err = sarif.DefaultRuleMetadataAugmentor()
	require.NoError(t, err)
}
