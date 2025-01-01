package fix

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/pkg/errors"
	tree_sitter "github.com/smacker/go-tree-sitter"
	tree_sitter_cpp "github.com/smacker/go-tree-sitter/cpp"
	tree_sitter_csharp "github.com/smacker/go-tree-sitter/csharp"
	tree_sitter_go "github.com/smacker/go-tree-sitter/golang"
	tree_sitter_java "github.com/smacker/go-tree-sitter/java"
	tree_sitter_javascript "github.com/smacker/go-tree-sitter/javascript"
	tree_sitter_python "github.com/smacker/go-tree-sitter/python"
	tree_sitter_ruby "github.com/smacker/go-tree-sitter/ruby"
	tree_sitter_rust "github.com/smacker/go-tree-sitter/rust"
	tree_sitter_typescript "github.com/smacker/go-tree-sitter/typescript/typescript"
)

func checkTreesitter(
	contents string,
	language utils.Language,
	dialect ...string,
) ([]fixdata.Problem, error) {
	parser := tree_sitter.NewParser()

	var treesitterLanguage *tree_sitter.Language

	switch language {
	case utils.LanguageJavascript:
		if len(dialect) > 0 && dialect[0] == "typescript" {
			treesitterLanguage = tree_sitter_typescript.GetLanguage()
		} else {
			treesitterLanguage = tree_sitter_javascript.GetLanguage()
		}
	case utils.LanguageCsharp:
		treesitterLanguage = tree_sitter_csharp.GetLanguage()
	case utils.LanguagePython:
		treesitterLanguage = tree_sitter_python.GetLanguage()
	case utils.LanguageRuby:
		treesitterLanguage = tree_sitter_ruby.GetLanguage()
	case utils.LanguageGo:
		treesitterLanguage = tree_sitter_go.GetLanguage()
	case utils.LanguageCpp:
		treesitterLanguage = tree_sitter_cpp.GetLanguage()
	case utils.LanguageJava:
		treesitterLanguage = tree_sitter_java.GetLanguage()
	case utils.LanguageRust:
		treesitterLanguage = tree_sitter_rust.GetLanguage()
	default:
		// should not happen (there's a test to prevent it)
		return []fixdata.Problem{}, errors.Errorf("unsupported language: %s", language)
	}
	parser.SetLanguage(treesitterLanguage)

	tree, err := parser.ParseCtx(context.Background(), nil, []byte(contents))

	if err != nil {
		// TODO: add log here?
		return []fixdata.Problem{newInvalidSyntaxProblem()}, nil
	}

	defer tree.Close()

	if tree.RootNode().HasError() {
		return []fixdata.Problem{newInvalidSyntaxProblem()}, nil
	} else {
		return newNoProblems(), nil
	}
}

func treesitterChecker(lang utils.Language, dialect ...string) ChangeChecker {
	// XXX this could probably be made a lot faster in practice by using the
	// tree-sitter incremental parsing capabilities
	return diffChecker(func(contents string) ([]fixdata.Problem, error) {
		return checkTreesitter(contents, lang, dialect...)
	})
}
