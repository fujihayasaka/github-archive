package v210turboscan

// Creates a placeholder rule for cases where a rule ID is specified for a result but no corresponding rule is included in the rule list.
func undetailedRule(id string) *Rule {
	return &Rule{
		Id: id,
	}
}

// UnknownRule is a placeholder rule associated with results that do
// not specify a rule.
var UnknownRule = &Rule{
	Id: "[unknown-rule]",
}

// RuleFromRuleId returns the Rule object associated with the given ruleId or nil, if none exists
func RuleFromRuleId(rules []*ReportingDescriptor, ruleId string) *Rule {
	for _, candidate := range rules {
		if candidate.Id == ruleId {
			return candidate
		}
	}
	return nil
}

// RuleFromRuleIndex returns the Rule object at the given index or nil, if none exists
func RuleFromRuleIndex(rules []*ReportingDescriptor, index uint) *Rule {
	if int(index) < len(rules) {
		return rules[index]
	}
	return nil
}
