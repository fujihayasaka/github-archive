# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class DependabotVulnerabilityAlertsTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner)
      end

      context  "verify_task" do
        test "returns false if there is no repo with a vulnerability alert" do
          refute DependabotVulnerabilityAlerts.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if there is a repo with a vulnerability alert" do
          @org.enable_vulnerability_updates_for_new_repos(actor: @org.owner)

          assert DependabotVulnerabilityAlerts.new(taskable: @org, user: @owner).verify_task
        end
      end
    end
  end
end
