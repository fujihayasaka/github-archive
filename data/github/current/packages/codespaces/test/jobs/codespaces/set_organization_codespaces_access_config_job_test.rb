# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Codespaces::SetOrganizationCodespacesAccessConfigJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @organization = create(:organization)
  end

  test "has a lock" do
    job1 = Codespaces::SetOrganizationCodespacesAccessConfigJob.new(organization_id: @organization.id, access_value: "disabled")
    job2 = Codespaces::SetOrganizationCodespacesAccessConfigJob.new(organization_id: @organization.id, access_value: "disabled")
    job3 = Codespaces::SetOrganizationCodespacesAccessConfigJob.new(organization_id: @organization.id, access_value: "all_users")

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "it updates the access_value" do
    assert_nil @organization.config.get(Configurable::OrganizationCodespacesUserLimit::KEY)

    Codespaces::SetOrganizationCodespacesAccessConfigJob.perform_now(organization_id: @organization.id, access_value: Configurable::OrganizationCodespacesUserLimit::ALL_USERS)
    assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS, @organization.reload.config.get(Configurable::OrganizationCodespacesUserLimit::KEY)
  end


  test "it updates the ownership_value" do
    refute @organization.has_organization_codespaces_ownership_setting?

    Codespaces::SetOrganizationCodespacesAccessConfigJob.perform_now(organization_id: @organization.id, ownership_value: Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION)
    assert_equal Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, @organization.reload.config.get(Configurable::OrganizationCodespacesOwnershipSetting::KEY)
  end

end
