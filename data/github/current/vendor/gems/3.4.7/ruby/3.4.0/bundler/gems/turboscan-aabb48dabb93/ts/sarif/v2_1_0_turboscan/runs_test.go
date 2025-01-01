package v210turboscan_test

import (
	"testing"

	"github.com/github/turboscan/ts/sarif/samples"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
)

func TestRun_Merge_ForASingleTool(t *testing.T) {
	s1 := samples.RequireSARIF(t, "testdata/example.sarif")
	s, err := s1.Runs[0].Merge(s1.Runs[0])
	require.NoError(t, err)
	require.Len(t, s.Results, len(s1.Runs[0].Results)*2)
	require.Len(t, s.Tool.Driver.Rules, len(s1.Runs[0].Tool.Driver.Rules)*2)

	// Different tools (Error)
	s2 := samples.RequireSARIF(t, "testdata/no_rules.sarif")
	_, err = s1.Runs[0].Merge(s2.Runs[0])
	require.Error(t, err)

	// Different invocations (Error)
	s3 := samples.RequireSARIF(t, "testdata/absolute_locations.sarif")
	s4 := samples.RequireSARIF(t, "testdata/absolute_locations_windows.sarif")
	_, err = s3.Runs[0].Merge(s4.Runs[0])
	require.Error(t, err)

	s5 := samples.RequireSARIF(t, "testdata/metrics.sarif")
	s6, err := s5.Runs[0].Merge(s5.Runs[0])
	require.NoError(t, err)
	require.NotNil(t, s6.Properties)
	require.Len(t, s6.Properties.MetricResults, len(s5.Runs[0].Properties.MetricResults)*2)
}

func TestRun_Merge_ForExtensions(t *testing.T) {
	s1 := samples.RequireSARIF(t, "testdata/rulesExtensions.sarif")

	require.Equal(t, 0, s1.Runs[1].Results[4].Rule.ToolComponent.Index)

	s, err := s1.Runs[0].Merge(s1.Runs[1])
	require.NoError(t, err)

	require.Equal(t, 0, s.Results[0].Rule.ToolComponent.Index)
	require.Equal(t, 0, s.Results[1].Rule.ToolComponent.Index)
	require.Equal(t, 0, s.Results[4].Rule.ToolComponent.Index)

	require.Equal(t, 1, s.Results[5].Rule.ToolComponent.Index)
	require.Equal(t, 1, s.Results[6].Rule.ToolComponent.Index)
	require.Equal(t, 1, s.Results[9].Rule.ToolComponent.Index)
}

func TestRun_Merge_Regression(t *testing.T) {
	// Test combining more than 2 runs
	s1 := samples.RequireSARIF(t, "testdata/invocations.sarif")
	s, err := s1.Runs[0].Merge(s1.Runs[4])
	require.NoError(t, err)
	_, err = s.Merge(s1.Runs[3])
	require.NoError(t, err)

	// Test invocations that do not have a working directory
	s2 := samples.RequireSARIF(t, "testdata/invocations2.sarif")
	_, err = s2.Runs[0].Merge(s2.Runs[1])
	require.NoError(t, err)
}

func TestRun_Merge_AccountingForAutomationIDs(t *testing.T) {
	s1 := samples.RequireSARIF(t, "testdata/automation_id_multiple_absent.sarif")
	_, err := s1.Runs[0].Merge(s1.Runs[1])
	require.Error(t, err)

	s2 := samples.RequireSARIF(t, "testdata/automation_id_multiple_consistent.sarif")
	s, err := s2.Runs[0].Merge(s2.Runs[1])
	require.NoError(t, err)
	require.Equal(t, s.AutomationDetails.Id, s2.Runs[0].AutomationDetails.Id)
	require.Equal(t, s.AutomationDetails.Id, s2.Runs[1].AutomationDetails.Id)

	s3 := samples.RequireSARIF(t, "testdata/automation_id_multiple_inconsistent.sarif")
	_, err = s3.Runs[0].Merge(s3.Runs[1])
	require.Error(t, err)

}

func TestRun_Merge_Notifications(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/notifications_multi_run.sarif")
	r, err := s.Runs[0].Merge(s.Runs[1])
	require.NoError(t, err)
	require.Equal(t, 4, len(r.Tool.Driver.Notifications))
	require.Equal(t, 2, len(r.Tool.Extensions[0].Notifications))
	require.Equal(t, 2, len(r.Tool.Extensions[1].Notifications))
	// Correct tool execution notifications are present
	require.Equal(t, "some markdown 1-1", r.Invocations[0].ToolExecutionNotifications[0].Message.Markdown)
	require.Equal(t, "some markdown 1-2", r.Invocations[0].ToolExecutionNotifications[1].Message.Markdown)
	require.Equal(t, "some markdown 2-1", r.Invocations[1].ToolExecutionNotifications[0].Message.Markdown)
	require.Equal(t, "some markdown 2-2", r.Invocations[1].ToolExecutionNotifications[1].Message.Markdown)

	// tool execution notifications refer to correct notifications
	tc, d, err := r.LookupNotification(r.Invocations[0].ToolExecutionNotifications[0])
	require.NoError(t, err)
	require.Equal(t, "CodeQL", tc.Name)
	require.Equal(t, "exampleid2", d.Id)
	tc, d, err = r.LookupNotification(r.Invocations[0].ToolExecutionNotifications[1])
	require.NoError(t, err)
	require.Equal(t, "ext-exampleid2", d.Id)
	require.Equal(t, "Extension 1", tc.Name)
	tc, d, err = r.LookupNotification(r.Invocations[1].ToolExecutionNotifications[0])
	require.NoError(t, err)
	require.Equal(t, "CodeQL", tc.Name)
	require.Equal(t, "exampleid4", d.Id)
	tc, d, err = r.LookupNotification(r.Invocations[1].ToolExecutionNotifications[1])
	require.NoError(t, err)
	require.Equal(t, "Extension 1", tc.Name)
	require.Equal(t, "ext-exampleid4", d.Id)
}

func TestLookupNotification(t *testing.T) {
	var actual *v2_1_0.ReportingDescriptor
	var err error

	s := samples.RequireSARIF(t, "testdata/tool-status-notification-augmented-with-code-scanning-properties.sarif")
	run := s.Runs[0]
	expected := run.Tool.Driver.Notifications[0]
	notification := run.Invocations[0].ToolExecutionNotifications[0]

	tc, actual, err := run.LookupNotification(notification)
	require.NoError(t, err)
	require.Equal(t, "CodeQL", tc.Name)
	require.Equal(t, expected, actual)

	// Locally modify the data in run.results to include an invalid index
	notification.Descriptor.Index = 10
	_, _, err = run.LookupNotification(notification)
	require.Error(t, err)
}
