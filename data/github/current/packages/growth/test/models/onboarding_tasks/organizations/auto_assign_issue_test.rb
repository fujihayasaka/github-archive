# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class AutoAssignIssueTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner)
        @repo = create(:repository, owner: @org)
        create(:demo_repository, organization: @org, repository: @repo)
      end

      def setup
        make_trusted_oauth_apps_owner
      end

      context "verify_task" do
        test "returns false if there is no workflow completed with autoassign.yml file" do
          create(:workflow, repository: @repo)

          refute AutoAssignIssue.new(taskable: @org, user: @owner).verify_task
        end

        test "returns false if there is a workflow completed with autoassign.yml file with wrong name" do
          check_suite = create(:check_suite_for_actions_app, repository: @repo, creator: @admin, name: "Proof HTML")
          check_suite.workflow_run

          refute AutoAssignIssue.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if there is a workflow completed with autoassign.yml file" do
          check_suite = create(:check_suite_for_actions_app, repository: @repo, creator: @admin, name: "Auto Assign")
          check_suite.workflow_run

          assert AutoAssignIssue.new(taskable: @org, user: @owner).verify_task
        end
      end
    end
  end
end unless GitHub.enterprise?
