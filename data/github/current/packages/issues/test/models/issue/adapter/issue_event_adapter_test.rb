# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class IssueEventAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  setup do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo, user: @user)
    @memex_project = create(:memex_project, owner: @user)
    @workflow = create(:memex_project_workflow, memex_project: @memex_project)
    @workflow_action = @workflow.actions.first
  end

  context "automated?" do
    test "adapting a converted from draft event" do
      event = create(:issue_event,
        event:         "converted_from_draft",
        repository:    @repo,
        project_id:    @memex_project.id,
        issue:         @issue,
        actor:         @user,
      )
      loader = Issue::ShowLoader.new @issue, @repo, @user, cap_filter: cap_authorizing_filter
      adapter = Issue::Adapter::ConvertedFromDraftEventAdapter.new(loader.context, event_id: event.id)

      assert_equal "converted_from_draft", adapter.event_name
      assert_equal false, adapter.automated?
    end

    test "adapting a converted from draft event for automated event" do
      event = create(:issue_event,
        event:         "converted_from_draft",
        repository:    @repo,
        project_id:    @memex_project.id,
        issue:         @issue,
        actor:         @user,
        performed_by_project_workflow_action_id: @workflow_action.id,
      )
      loader = Issue::ShowLoader.new @issue, @repo, @user, cap_filter: cap_authorizing_filter
      adapter = Issue::Adapter::ConvertedFromDraftEventAdapter.new(loader.context, event_id: event.id)

      assert_equal "converted_from_draft", adapter.event_name
      assert_equal true, adapter.automated?
    end
  end
end
