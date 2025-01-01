# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class OrganizationsBranchProtectionRuleTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner)
        @repo = create(:repository, owner: @org)
        create(:demo_repository, organization: @org, repository: @repo)
      end

      context  "verify_task" do
        test "returns false if there is no repo with a protected branch in the org" do
          refute BranchProtectionRule.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if there is a repo with a protected branch in the org" do
          create(:protected_branch, repository: @repo)

          assert BranchProtectionRule.new(taskable: @org, user: @owner).verify_task
        end
      end
    end
  end
end
