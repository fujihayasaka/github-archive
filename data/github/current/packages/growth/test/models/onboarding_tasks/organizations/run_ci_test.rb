# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class RunCiTest < GitHub::TestCase
      fixtures do
        @org  = make_trusted_oauth_apps_owner
        create(:launch_integration)
        @repo = create(:repository, owner: @org)
        create(:demo_repository, organization: @org, repository: @repo)
      end

      setup do
        GitHub.stubs(:actions_enabled?).returns(true)
      end

      context  "verify_task" do
        test "returns false if there is no manual executed workflow from Proof HTML" do
          create(:check_suite_for_actions_app, repository: @repo, name: "Proof HTML", event: "push")

          refute RunCi.new(taskable: @org, user: @org.admin).verify_task
        end

        test "returns true if there is a executed workflow from Proof HTML" do
          create(:check_suite_for_actions_app, repository: @repo, name: "Proof HTML", event: "workflow_dispatch")

          assert RunCi.new(taskable: @org, user: @org.admin).verify_task
        end
      end
    end
  end
end
