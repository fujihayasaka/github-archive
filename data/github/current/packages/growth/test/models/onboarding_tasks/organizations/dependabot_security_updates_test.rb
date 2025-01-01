# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class DependabotSecurityUpdatesTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner)
      end

      context  "verify_task" do
        test "returns false if dependabot is not installed" do
          refute DependabotSecurityUpdates.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if dependabot is installed" do
          @org.enable_security_alerts_for_new_repos(actor: @org.owner)

          assert DependabotSecurityUpdates.new(taskable: @org, user: @owner).verify_task
        end
      end
    end
  end
end
