# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInstallationIntegrationInstallationsTest < GitHub::TestCase
  fixtures do
    @org          = create(:organization)
    @member       = create(:user)
    @user         = create(:user)
    @installation = make_integration_installation(target: @org)

    @org.add_member(@member)
  end

  context "when adding a member" do
    test "queues a job to calculate the rate limit" do
      assert_enqueued_with job: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit", args: [@installation.id] do
        @org.add_member(@user)
      end
    end
  end

  context "when removing a member" do
    test "queues a job to calculate the rate limit" do
      @org.remove_member!(@member)
      perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob)
      assert_enqueued_with job: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit", args: [@installation.id]
    end
  end
end
