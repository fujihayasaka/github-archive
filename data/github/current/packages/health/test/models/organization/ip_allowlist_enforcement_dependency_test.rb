# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationIpAllowlistEnforcementDependencyTest < GitHub::TestCase
  fixtures do
    @org = create :business_plus_org
    @integration = create :integration
    make_integration_installation integration: @integration, target: @org
    @business_owned_org = create :organization
    @business = create :business, organizations: [@business_owned_org]
  end

  context "#ip_allowlist_enabled_on_business?" do
    test "returns false if the organization does not belong to a business" do
      assert_nil @org.business
      refute_predicate @org, :ip_allowlist_enabled_on_business?
    end

    test "returns false if the organization's business does not have IP allow list enabled" do
      refute_predicate @business_owned_org, :ip_allowlist_enabled_on_business?
    end

    test "returns true if the organization's business has IP allow list enabled" do
      @business.enable_ip_allowlist(actor: @business.admins.first)
      assert_predicate @business_owned_org, :ip_allowlist_enabled_on_business?
    end
  end

  context "#filtered_ip_allowlist_entries" do
    test "returns filtered IP allow list entries owned by the org" do
      matching = create :ip_allowlist_entry, owner: @org, allow_list_value: "1.2.3.4"
      not_matching = create :ip_allowlist_entry, owner: @org, allow_list_value: "4.3.2.1"
      assert_same_elements [matching], @org.filtered_ip_allowlist_entries(query: "1.2")
    end
  end

  context "#filtered_installed_app_ip_allowlist_entries" do
    test "returns filtered IP allow list entries for apps installed on the org" do
      matching = create :ip_allowlist_entry, owner: @integration, allow_list_value: "1.2.3.4"
      not_matching = create :ip_allowlist_entry, owner: @integration, allow_list_value: "4.3.2.1"
      assert_same_elements [matching], @org.filtered_installed_app_ip_allowlist_entries(query: "1.2")
    end
  end
end if GitHub.ip_allowlists_available?
