# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessActionsDependencyTest < GitHub::TestCase
  context "Default workflow permissions" do
    test "workflow write permissions are set to write for new businesses" do
      biz = create :business

      if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
        assert biz.actions_default_workflow_permissions_read_only?
      else
        refute biz.actions_default_workflow_permissions_read_only?
      end
    end

    test "workflow PR approval permissions are set to disallow for new businesses" do
      biz = create :business

      if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
        refute biz.actions_workflow_permission_can_approve_pr?
      else
        assert biz.actions_workflow_permission_can_approve_pr?
      end
    end
  end
end
