# typed: true
# frozen_string_literal: true

require "test_helper"

class Hook::Payload::SubIssuesPayloadTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @parent_issue = create(:issue, repository: @repo)
    @sub_issue = create(:issue, repository: @repo)
    @user = create(:user)
  end

  def sub_issue_event(action: :sub_issue_added, parent_issue_id: @parent_issue.id, child_issue_id: @sub_issue.id, actor_id: nil)
    Hook::Event::SubIssuesEvent.new(
      action: action,
      parent_issue_id: parent_issue_id,
      child_issue_id: child_issue_id,
      actor_id: actor_id
    )
  end

  Hook::Event::SubIssuesEvent.actions.each do |action|
    test "for #{action} event, includes all fields" do
      event = sub_issue_event(action: action)
      payload = Hook::Payload::SubIssuesPayload.new(event).to_payload_hash

      assert_equal event.action, payload[:action]
      assert payload[:sub_issue].present?
      assert payload[:sub_issue_id].present?
      assert payload[:parent_issue].present?
      assert payload[:parent_issue_id].present?

      if [:sub_issue_added, :sub_issue_removed].include?(action.to_sym)
        assert payload[:sub_issue_repo].present?
      else
        assert_nil payload[:sub_issue_repo]
      end

      if [:parent_issue_added, :parent_issue_removed].include?(action.to_sym)
        assert payload[:parent_issue_repo].present?
      else
        assert_nil payload[:parent_issue_repo]
      end
    end
  end
end
