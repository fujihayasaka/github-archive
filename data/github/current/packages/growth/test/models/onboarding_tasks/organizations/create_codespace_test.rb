# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Organizations
    class CreateCodespaceTest < GitHub::TestCase
      fixtures do
        @owner = create(:user)
        @org = create(:organization, login: "ACME", admin: @owner, plan: GitHub::Plan.business)
        @repo = create(:repository, owner: @org)
        create(:demo_repository, organization: @org, repository: @repo)
      end

      context  "verify_task" do
        test "returns false if there is no repo with codespace enabled" do
          refute CreateCodespace.new(taskable: @org, user: @owner).verify_task
        end

        test "returns true if there is a repo with Codespace enabled in the org" do
          create(:codespace, repository: @repo)

          assert CreateCodespace.new(taskable: @org, user: @owner).verify_task
        end
      end
    end unless GitHub.enterprise?
  end
end
