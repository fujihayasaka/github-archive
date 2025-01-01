package v210turboscan

import "github.com/pkg/errors"

// Determine the tool component referenced by the result (see §3.52.7)
func (tool *Tool) toolComponentFromReference(rule *ReportingDescriptorReference) (ToolComponentIndicator, *ToolComponent, error) {

	// §3.27.7: If rule is absent, it SHALL default to a reportingDescriptorReference object whose id property is set
	//          to thisObject.ruleId and whose index property is set to thisObject.ruleIndex.
	// §3.52.7: If toolComponent is absent, theComponent shall be taken to be theTool.driver
	if rule == nil || rule.ToolComponent == nil {
		return errOnNilToolComponent(ToolComponentDriver, tool.Driver)
	}

	tcRef := rule.ToolComponent
	// If neither index (§3.54.4) nor guid (§3.54.5) is present, theComponent SHALL be theTool.driver
	// Note: We're setting a missing index to -1 in ts/sarif/v2_1_0_turboscan/sarif.go
	if tcRef.Index == -1 && tcRef.Guid == "" {
		return errOnNilToolComponent(ToolComponentDriver, tool.Driver)
	}
	// If index is present, theComponent SHALL be the object at array index index within theTool.extensions (§3.18.3).
	if tcRef.Index > -1 {
		if tcRef.Index >= len(tool.Extensions) {
			return ToolComponentUnknown, nil, errors.Errorf("toolComponentReference.index %d not found", tcRef.Index)
		}

		return errOnNilToolComponent(ToolComponentIndicator(tcRef.Index), tool.Extensions[tcRef.Index])
	}

	// If index is absent and guid is present, theComponent SHALL be either theTool.driver or an element
	// of theTool.extensions, whichever one has a matching guid property.
	if tcRef.Guid != "" {
		if tcRef.Guid == tool.Driver.Guid {
			return errOnNilToolComponent(ToolComponentDriver, tool.Driver)
		}

		for i, ext := range tool.Extensions {
			if tcRef.Guid == ext.Guid {
				return errOnNilToolComponent(ToolComponentIndicator(i), tool.Extensions[i])
			}
		}

		return ToolComponentUnknown, nil, errors.Errorf("toolComponentReference.guid %s not found", tcRef.Guid)
	}

	// This should never happen
	return ToolComponentUnknown, nil, errors.New("Broken toolComponentReference ")
}

// errOnNilToolComponent returns an error if the tool component is nil (null in the json document)
// we will be able to remove this check once the document is being fully validated
func errOnNilToolComponent(tcInd ToolComponentIndicator, tc *ToolComponent) (ToolComponentIndicator, *ToolComponent, error) {
	if tc == nil {
		return ToolComponentUnknown, nil, errors.New("toolComponent was not present")
	}
	return tcInd, tc, nil
}
