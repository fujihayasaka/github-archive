# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationConfigurationEntriesTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @business_organization = create :organization
    @business = create(:business, organizations: [@business_organization])
    @organization = create :organization
  end

  test "inherit from GitHub without a business membership" do
    assert_equal GitHub, @organization.configuration_owner
  end

  test "inherit from a business with a business membership when businesses enabled" do
    assert_equal @business, @business_organization.configuration_owner
    @business.allow_private_repository_forking(actor: @business.owners.first)
    assert @business_organization.allow_private_repository_forking?
  end

  test "can be set and read" do
    @business_organization.allow_private_repository_forking(actor: @business_organization.admin)
    assert @business_organization.allow_private_repository_forking?
  end

  test "includes audit log information" do
    events = assert_performed_audit_entries(count: 1, only: "config_entry.create") do
      @business_organization.allow_private_repository_forking(actor: @business_organization.admin)
    end

    assert_equal last_performed_audit_entries, events
    expected_payload = {
      target_type: "User",
      org: @business_organization.login,
      org_id: @business_organization.id
    }
    assert_subset_hash expected_payload, events.first
  end
end
