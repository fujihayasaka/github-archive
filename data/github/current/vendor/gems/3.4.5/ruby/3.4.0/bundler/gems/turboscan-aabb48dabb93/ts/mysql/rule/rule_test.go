package rule

import (
	"context"
	"fmt"
	"strings"
	"testing"

	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	"github.com/stretchr/testify/require"
)

const tagsPerRuleLimit = 5

var tool = &ts.ToolVersion{
	Name:    "CodeQL",
	Version: "2.0.1",
	ToolID:  1519,
	Tool: &ts.Tool{
		ID:            1519,
		GUID:          "",
		CanonicalName: "CodeQL",
	},
}

var globalTool = &ts.Tool{
	ID:            123,
	CanonicalName: "ABC",
}

func TestSaveAndLoad(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	rs1 := NewService(db)

	run := samples.RequireSARIF(t, "../sarif/testdata/rules.sarif").Runs[0]
	rule1, _, err := sarif.RuleFromSarifRule(run.Tool.Driver.Rules[0], globalTool, tagsPerRuleLimit)
	require.NoError(t, err)
	err = rs1.FindOrCreate(ctx, []*ts.Rule{rule1})
	require.NoError(t, err)

}

// TestRuleTags checks that the Tags are included when calculating a rule hash.
func TestRuleTags(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	rs := NewService(db)

	rule := ts.Rule{
		ToolID:          globalTool.ID,
		SarifIdentifier: "abc",
	}

	err := rs.FindOrCreate(ctx, []*ts.Rule{&rule})
	require.NoError(t, err)

	rule2 := ts.Rule{
		ToolID:          globalTool.ID,
		SarifIdentifier: "abc",
	}
	rule2.SetTags([]string{"red"})

	err = rs.FindOrCreate(ctx, []*ts.Rule{&rule2})
	require.NoError(t, err)
	dbtest.RequireCount(t, 1, db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule2.ID}))

	rule3 := ts.Rule{
		ToolID:          globalTool.ID,
		SarifIdentifier: "abc",
	}
	rule3.SetTags([]string{"blue"})
	err = rs.FindOrCreate(ctx, []*ts.Rule{&rule3})
	require.NoError(t, err)

	var tags []ts.RuleTag
	err = db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule3.ID}).Find(&tags).Error
	require.NoError(t, err)
	require.Equal(t, 1, len(tags))
	require.Equal(t, "blue", tags[0].Tag)
}

func TestFindExisting(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	rs1 := NewService(db)

	run := samples.RequireSARIF(t, "../sarif/testdata/rules.sarif").Runs[0]
	rule1, _, err := sarif.RuleFromSarifRule(run.Tool.Driver.Rules[0], globalTool, tagsPerRuleLimit)
	require.NoError(t, err)
	err = rs1.FindOrCreate(ctx, []*ts.Rule{rule1})
	require.NoError(t, err)

	rule1Copy := &ts.Rule{}
	*rule1Copy = *rule1
	// blank out the the ID field as it should be restored by the FindOrCreate operation
	rule1Copy.ID = 0

	rule2, _, err := sarif.RuleFromSarifRule(run.Tool.Driver.Rules[0], globalTool, tagsPerRuleLimit)
	require.NoError(t, err)
	err = rs1.FindOrCreate(ctx, []*ts.Rule{rule1Copy, rule2})
	require.NoError(t, err)

	require.Equal(t, rule1Copy.ID, rule1.ID)
}

func TestFindMany(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	rs1 := NewService(db)

	rules := make([]*ts.Rule, 250)

	for i := 0; i < len(rules); i++ {
		rules[i] = &ts.Rule{
			ToolID:          globalTool.ID,
			SarifIdentifier: fmt.Sprintf("abc-%d", i),
		}
	}

	err := rs1.FindOrCreate(ctx, rules)
	require.NoError(t, err)

	dbtest.RequireCount(t, 250, db.Model(&ts.Rule{}))

	// insert the same rules again (sans IDs)
	for i := 0; i < len(rules); i++ {
		rules[i] = &ts.Rule{
			ToolID:          globalTool.ID,
			SarifIdentifier: fmt.Sprintf("abc-%d", i),
		}
	}

	// include 25 new rules in the batch
	for i := 0; i < 25; i++ {
		rules = append(rules, &ts.Rule{
			ToolID:          globalTool.ID,
			SarifIdentifier: fmt.Sprintf("xyz-%d", i),
		})
	}

	err = rs1.FindOrCreate(ctx, rules)
	require.NoError(t, err)

	dbtest.RequireCount(t, 275, db.Model(&ts.Rule{}))
}

func TestRuleTagChangesORIG(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	ruleS := NewService(db)

	// Create a Rule with no tags
	rule := &ts.Rule{
		ToolID:          tool.Tool.ID,
		SarifIdentifier: "abc",
	}
	err := ruleS.FindOrCreate(ctx, []*ts.Rule{rule})
	require.NoError(t, err)
	ruleID := rule.ID

	// Add a tag and update - check that the db has one entry
	rule = &ts.Rule{
		ToolID:          tool.Tool.ID,
		SarifIdentifier: "abc",
	}
	rule.SetTags([]string{"red"})
	err = ruleS.FindOrCreate(ctx, []*ts.Rule{rule})
	require.NoError(t, err)

	// should not alter the original rule
	dbtest.RequireCount(t, 0, db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: ruleID}))
	dbtest.RequireCount(t, 1, db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule.ID}))

	// Rename a tag - check the value in the db
	rule = &ts.Rule{
		ToolID:          tool.Tool.ID,
		SarifIdentifier: "abc",
	}
	rule.SetTags([]string{"blue"})
	err = ruleS.FindOrCreate(ctx, []*ts.Rule{rule})
	require.NoError(t, err)

	var tags []ts.RuleTag
	err = db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule.ID}).Find(&tags).Error
	require.NoError(t, err)
	require.Equal(t, 1, len(tags))
	require.Equal(t, "blue", tags[0].Tag)

	// Recreate rule with same tag - should not change the count
	rule = &ts.Rule{
		ToolID:          tool.Tool.ID,
		SarifIdentifier: "abc",
	}
	rule.SetTags([]string{"blue"})
	err = ruleS.FindOrCreate(ctx, []*ts.Rule{rule})
	require.NoError(t, err)
	dbtest.RequireCount(t, 1, db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule.ID}))

	// Remove a tag and update - check that the db has no entry
	rule = &ts.Rule{
		ToolID:          tool.Tool.ID,
		SarifIdentifier: "abc",
	}
	rule.SetTags([]string{})
	err = ruleS.FindOrCreate(ctx, []*ts.Rule{rule})
	require.NoError(t, err)
	dbtest.RequireCount(t, 0, db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule.ID}))
}

func TestHelpTruncation(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	ruleS := NewService(db)

	shortEnoughMarkdown := strings.Repeat("?", 64*1024)
	multiformatMessageString := v2_1_0.MultiformatMessageString{Markdown: shortEnoughMarkdown}
	sarifRule := v2_1_0.Rule{Help: &multiformatMessageString}
	databaseRule, _, err := sarif.RuleFromSarifRule(&sarifRule, tool.Tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Equal(t, databaseRule.Help, shortEnoughMarkdown)

	err = ruleS.FindOrCreate(ctx, []*ts.Rule{databaseRule})
	require.NoError(t, err)

	tooLongMarkdown := strings.Repeat("?", 64*1024+1)
	multiformatMessageString = v2_1_0.MultiformatMessageString{Markdown: tooLongMarkdown}
	sarifRule = v2_1_0.Rule{Help: &multiformatMessageString}
	databaseRule, _, err = sarif.RuleFromSarifRule(&sarifRule, tool.Tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Equal(t, databaseRule.Help, shortEnoughMarkdown)
}

func TestRuleFromSarifRuleTagsAreCaseInsensitive(t *testing.T) {
	sarifRule := &v2_1_0.Rule{Properties: &v2_1_0.ReportingDescriptorPropertyBag{Tags: []string{"blue", "Blue", "red"}}}

	rule, _, err := sarif.RuleFromSarifRule(sarifRule, tool.Tool, tagsPerRuleLimit)

	require.NoError(t, err)
	l, err := rule.GetTags()
	require.NoError(t, err)
	require.Len(t, l, 2)
}

func TestRuleNameTrucation(t *testing.T) {
	inRule := &v2_1_0.Rule{
		Name: strings.Repeat("a", 1024),
	}
	outRule, _, err := sarif.RuleFromSarifRule(inRule, tool.Tool, tagsPerRuleLimit)
	require.NoError(t, err)
	require.Len(t, outRule.Name, 255)
}
