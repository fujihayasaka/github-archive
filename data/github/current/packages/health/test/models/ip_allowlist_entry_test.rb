# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.ip_allowlists_available?
  class IpAllowlistEntryTest < GitHub::TestCase
    include HydroTestHelpers
    include GitHub::DatabaseQueryWarningsTestHelpers

    fixtures do
      if GitHub.single_business_environment?
        GitHub::Enterprise.ensure_business!
        @business = GitHub.global_business
        @business.add_owner(create(:user), actor: nil)
      else
        @business = create :business
      end
    end

    context "validations" do
      test "owner must be present" do
        entry = build :ip_allowlist_entry, owner: nil
        refute_predicate entry, :valid?
        assert_includes entry.errors[:owner], "can't be blank"
      end

      test "owner can be a Business" do
        entry = create :ip_allowlist_entry, owner: @business
        assert_predicate entry, :valid?
      end

      test "owner can be an Organization" do
        entry = create :ip_allowlist_entry, owner: create(:business_plus_org)
        assert_predicate entry, :valid?
      end

      test "owner can be an Integration" do
        entry = create :ip_allowlist_entry, owner: create(:integration)
        assert_predicate entry, :valid?
      end

      test "owner cannot be another type of object" do
        something_else = create :page
        entry = build :ip_allowlist_entry, owner: something_else
        refute_predicate entry, :valid?
        assert_includes entry.errors[:owner], "must be an enterprise account, organization, or GitHub App"
      end

      test "org owner must have business_plus plan" do
        entry = build :ip_allowlist_entry, owner: create(:organization, plan: GitHub::Plan::BUSINESS)
        refute_predicate entry, :valid?
        assert_includes entry.errors[:owner], "doesn't have an eligible plan for an IP allow list"
      end

      test "name can be blank" do
        entry = create :ip_allowlist_entry, owner: @business, name: ""
        assert_predicate entry, :valid?
      end

      test "name cannot exceed 255 characters if provided" do
        name = "E" * 300
        entry = build :ip_allowlist_entry, owner: @business, name: name
        refute_predicate entry, :valid?
        assert_includes entry.errors[:name], "is too long (maximum is 255 characters)"
      end

      test "name must be unicode3 if provided" do
        entry = build :ip_allowlist_entry, owner: @business, name: "Popcorn network 🍿"
        refute_predicate entry, :valid?
        assert_includes entry.errors[:name], "doesn't accept 4-byte Unicode"
      end

      test "allow_list_value must be present" do
        entry = build :ip_allowlist_entry, allow_list_value: nil
        refute_predicate entry, :valid?
        assert_includes entry.errors[:allow_list_value], "can't be blank"
      end

      test "allow_list_value can be an IPv4 address in CIDR notation" do
        entry = create :ip_allowlist_entry, allow_list_value: "192.168.100.0/22"
        assert_predicate entry, :valid?
      end

      test "allow_list_value can be an IPv4 address without CIDR notation" do
        entry = create :ip_allowlist_entry, allow_list_value: "192.168.103.201"
        assert_predicate entry, :valid?
      end

      test "allow_list_value can be an IPv6 address in CIDR notation" do
        entry = create :ip_allowlist_entry, allow_list_value: "2001:db8::/48"
        assert_predicate entry, :valid?
      end

      test "allow_list_value can be an IPv6 address without CIDR notation" do
        entry = create :ip_allowlist_entry, allow_list_value: "2001:db8:0:ffff:ffff:ffff:ffff:ffff"
        assert_predicate entry, :valid?
      end

      test "allow_list_value cannot be invalid" do
        entry = build :ip_allowlist_entry, allow_list_value: "invalid CIDR notation"
        refute_predicate entry, :valid?
        assert_includes \
          entry.errors.full_messages,
          "Allow list value must be a valid IP address or range of addresses in CIDR notation"
      end

      test "range values are generated for IPv4 address in CIDR notation" do
        entry = create :ip_allowlist_entry, allow_list_value: "192.168.100.0/22"
        assert_predicate entry, :valid?

        range = IPAddr.new(entry.allow_list_value).to_range
        assert_equal range.first.hton, entry.range_from
        assert_equal range.last.hton, entry.range_to
      end

      test "range values are generated for single IPv4 address" do
        entry = create :ip_allowlist_entry, allow_list_value: "192.168.100.1"
        assert_predicate entry, :valid?

        range = IPAddr.new(entry.allow_list_value).to_range
        assert_equal range.first.hton, entry.range_from
        assert_equal range.last.hton, entry.range_to
        assert_equal entry.range_from, entry.range_to
      end

      test "range values are generated for IPv6 address in CIDR notation" do
        entry = create :ip_allowlist_entry, allow_list_value: "2001:db8::/48"
        assert_predicate entry, :valid?

        range = IPAddr.new(entry.allow_list_value).to_range
        assert_equal range.first.hton, entry.range_from
        assert_equal range.last.hton, entry.range_to
      end

      test "range values are generated for single IPv6 address" do
        entry = create :ip_allowlist_entry, allow_list_value: "2001:db8:0:ffff:ffff:ffff:ffff:ffff"
        assert_predicate entry, :valid?

        range = IPAddr.new(entry.allow_list_value).to_range
        assert_equal range.first.hton, entry.range_from
        assert_equal range.last.hton, entry.range_to
        assert_equal entry.range_from, entry.range_to
      end

      test "range values are re-generated on update" do
        entry = create :ip_allowlist_entry, allow_list_value: "192.168.100.0/22"
        new_cidr = "192.168.100.0/8"
        entry.update allow_list_value: new_cidr
        assert_predicate entry, :valid?

        new_range = IPAddr.new(new_cidr).to_range
        assert_equal new_range.first.hton, entry.range_from
        assert_equal new_range.last.hton, entry.range_to
      end

      context "prevent actor from being locked out" do
        test "actor cannot be locked out on create with no existing entries" do
          @business.enable_ip_allowlist actor: @business.owners.first
          entry = build :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22", actor_ip: "1.1.1.1"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "This change would prevent you from accessing the account from your current IP address"
        end

        test "actor cannot be locked out on create with existing entries" do
          @business.enable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = build :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22", actor_ip: "1.1.1.1"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "This change would prevent you from accessing the account from your current IP address"
        end

        test "actor cannot be locked out on create when entering an invalid allow_list_value" do
          @business.enable_ip_allowlist actor: @business.owners.first
          entry = build :ip_allowlist_entry, \
            owner: @business, allow_list_value: "1.1.1.one", actor_ip: "1.1.1.1"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "Allow list value must be a valid IP address or range of addresses in CIDR notation"
        end

        test "entry with originating IP can be created by actor with no existing entries" do
          @business.enable_ip_allowlist actor: @business.owners.first
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22", actor_ip: "192.168.100.10"
          assert_predicate entry, :valid?
        end

        test "entry with non-originating IP can be created by actor if matching existing entry exists" do
          @business.enable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22", actor_ip: "200.168.100.10"
          assert_predicate entry, :valid?
        end

        test "entry with non-originating IP can be created by actor if IP allow list disabled" do
          @business.disable_ip_allowlist actor: @business.owners.first
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22", actor_ip: "200.168.100.10"
          assert_predicate entry, :valid?
        end

        test "actor cannot be locked out on update of allow_list_value with single entry" do
          @business.enable_ip_allowlist actor: @business.owners.first
          entry = create :ip_allowlist_entry, owner: @business, allow_list_value: "192.168.100.0/22"
          assert_predicate entry, :valid?

          entry.update allow_list_value: "200.168.100.0/22", actor_ip: "192.168.100.32"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "This change would prevent you from accessing the account from your current IP address"
        end

        test "actor cannot be locked out on update when entering invalid allow_list_value" do
          @business.enable_ip_allowlist actor: @business.owners.first
          entry = create :ip_allowlist_entry, owner: @business, allow_list_value: "192.168.100.0/22"
          assert_predicate entry, :valid?

          entry.update allow_list_value: "200.168.100.hello", actor_ip: "192.168.100.32"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "Allow list value must be a valid IP address or range of addresses in CIDR notation"
        end

        test "actor cannot be locked out on update of allow_list_value with multiple entries" do
          @business.enable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "1.1.1.1/22"

          entry.update allow_list_value: "192.168.100.0/22", actor_ip: "1.1.1.1"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "This change would prevent you from accessing the account from your current IP address"
        end

        test "actor cannot be locked out on update of active state with multiple entries" do
          @business.enable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "1.1.1.1/22"

          entry.update active: false, actor_ip: "1.1.1.1"
          refute_predicate entry, :valid?
          assert_includes \
            entry.errors.full_messages,
            "This change would prevent you from accessing the account from your current IP address"
        end

        test "can update allow_list_value with value matching originating IP" do
          @business.enable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22"

          entry.update allow_list_value: "1.1.1.1/22", actor_ip: "1.1.1.1"
          assert_predicate entry, :valid?
        end

        test "can activate inactive entry when allow_list_value matches originating IP" do
          @business.enable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = create :ip_allowlist_entry, \
            owner: @business, active: false, allow_list_value: "192.168.100.0/22"

          entry.update active: true, actor_ip: "192.168.100.10"
          assert_predicate entry, :valid?
        end

        test "can update allow_list_value with value not matching originating IP if IP allow list disabled" do
          @business.disable_ip_allowlist actor: @business.owners.first
          create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "200.168.100.0/22"
          entry = create :ip_allowlist_entry, \
            owner: @business, allow_list_value: "192.168.100.0/22"

          entry.update allow_list_value: "1.1.1.1/22", actor_ip: "8.8.8.8"
          assert_predicate entry, :valid?
        end

        test "lock out prevention does not apply to entries owned by GitHub Apps" do
          app = create :integration
          entry = build :ip_allowlist_entry, \
            owner: app, allow_list_value: "192.168.100.0/22", actor_ip: "1.1.1.1"
          assert_predicate entry, :valid?
          assert entry.save
        end
      end
    end

    context "destroy" do
      test "actor cannot be locked out on destroy with single entry" do
        @business.enable_ip_allowlist actor: @business.owners.first
        entry = create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "192.168.100.0/22"

        entry.actor_ip = "192.168.100.10"
        refute entry.destroy
        assert_includes \
          entry.errors.full_messages,
          "This change would prevent you from accessing the account from your current IP address"
      end

      test "actor cannot be locked out on destroy with multiple entries" do
        @business.enable_ip_allowlist actor: @business.owners.first
        create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "10.10.10.10/22"
        entry = create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "192.168.100.0/22"

        entry.actor_ip = "192.168.100.10"
        refute entry.destroy
        assert_includes \
          entry.errors.full_messages,
          "This change would prevent you from accessing the account from your current IP address"
      end

      test "can destroy entry if entry with matching allow_list_value remains" do
        @business.enable_ip_allowlist actor: @business.owners.first
        create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "192.168.100.0/22"
        entry = create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "10.10.10.10/22"

        entry.actor_ip = "192.168.100.10"
        assert entry.destroy
        assert_nil IpAllowlistEntry.find_by id: entry.id
      end

      test "can destroy only matching entry if IP allow list disabled" do
        @business.disable_ip_allowlist actor: @business.owners.first
        create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "10.10.10.10/22"
        entry = create :ip_allowlist_entry, \
          owner: @business, allow_list_value: "192.168.100.0/22"

        entry.actor_ip = "192.168.100.10"
        assert entry.destroy
        assert_nil IpAllowlistEntry.find_by id: entry.id
      end
    end

    context "#usable_for" do
      test "returns entries for Business" do
        business_entry = create :ip_allowlist_entry, owner: @business
        assert_same_elements [business_entry], IpAllowlistEntry.usable_for(@business).all
      end

      test "returns entries for Organization" do
        org = create :business_plus_org
        org_entry = create :ip_allowlist_entry, owner: org
        assert_same_elements [org_entry], IpAllowlistEntry.usable_for(org).all
      end

      test "returns inherited entries from Business for Business-owned Organization when IP allow list enabled on Business" do
        org = create :business_plus_org
        org_entry = create :ip_allowlist_entry, owner: org
        business_entry = create :ip_allowlist_entry, owner: @business
        @business.enable_ip_allowlist actor: @business.owners.first
        @business.add_organization org
        org.reload
        assert_same_elements \
          [org_entry, business_entry],
          IpAllowlistEntry.usable_for(org).all
      end

      test "does not return inherited entries from Business for Business-owned Organization when IP allow list disabled on Business" do
        org = create :business_plus_org
        org_entry = create :ip_allowlist_entry, owner: org
        business_entry = create :ip_allowlist_entry, owner: @business
        @business.add_organization org
        org.reload
        assert_same_elements \
          [org_entry],
          IpAllowlistEntry.usable_for(org).all
      end

      test "returns entries for Integration" do
        integration = create :integration
        integration_entry = create :ip_allowlist_entry, owner: integration
        assert_same_elements [integration_entry], IpAllowlistEntry.usable_for(integration).all
      end

      test "returns entries for IntegrationInstallation" do
        org = create :business_plus_org
        integration_installation = make_integration_installation target: org
        integration_entry = create :ip_allowlist_entry, owner: integration_installation.integration
        assert_same_elements [integration_entry], IpAllowlistEntry.usable_for(integration_installation).all
      end
    end

    context "#installed_for" do
      test "returns entries for an app installed on an enterprise" do
        other_entry = create :ip_allowlist_entry, owner: @business
        integration_installation = make_integration_installation target: @business, permissions: { Business::Resources.subject_types.first => :read }
        integration_entry = create :ip_allowlist_entry, owner: integration_installation.integration
        assert_same_elements \
          [integration_entry],
          IpAllowlistEntry.installed_for(@business).all
      end

      test "returns entries for an app installed on an org" do
        org = create :business_plus_org
        other_entry = create :ip_allowlist_entry, owner: org
        integration_installation = make_integration_installation target: org
        integration_entry = create :ip_allowlist_entry, owner: integration_installation.integration
        assert_same_elements \
          [integration_entry],
          IpAllowlistEntry.installed_for(org).all
      end

      test "returns no entries for app itself" do
        org = create :business_plus_org
        integration_installation = make_integration_installation target: org
        integration_entry = create :ip_allowlist_entry, owner: integration_installation.integration
        assert_empty IpAllowlistEntry.installed_for(integration_installation.integration).all
      end
    end

    context "#active" do
      test "returns only active IP allow list entries" do
        active = create :ip_allowlist_entry, :org, active: true, allow_list_value: "1.1.1.0/24"
        inactive = create :ip_allowlist_entry, :org, active: false, allow_list_value: "8.8.8.0/24"
        assert_same_elements \
          [active],
          IpAllowlistEntry.active.all
      end
    end

    context "#matching_ip" do
      test "returns only matching entries for IPv4 address" do
        ip = "8.8.8.8"
        not_matching_ipv4 = create :ip_allowlist_entry, :org, allow_list_value: "1.1.1.0/24"
        not_matching_ipv6 = create :ip_allowlist_entry, :org, allow_list_value: "2620:0:2d0:200::7"
        matching_ipv4 = create :ip_allowlist_entry, :org, allow_list_value: "8.8.8.0/24"
        assert_same_elements \
          [matching_ipv4],
          IpAllowlistEntry.matching_ip(ip).all
      end

      test "returns only matching entries for IPv6 address" do
        ip = "2001:db8:0:ffff:ffff:ffff:ffff:bf66"
        not_matching_ipv4 = create :ip_allowlist_entry, :org, allow_list_value: "1.1.1.0/24"
        not_matching_ipv6 = create :ip_allowlist_entry, :org, allow_list_value: "2620:0:2d0:200::7"
        matching_ipv6  = create :ip_allowlist_entry, :org, allow_list_value: "2001:db8::/48"
        assert_same_elements \
          [matching_ipv6],
          IpAllowlistEntry.matching_ip(ip).all
      end

      test "returns only matching entries for IPv4 address in IPv6 notation" do
        ip = "::ffff:8.8.8.8"
        not_matching_ipv4 = create :ip_allowlist_entry, :org, allow_list_value: "1.1.1.0/24"
        not_matching_ipv6 = create :ip_allowlist_entry, :org, allow_list_value: "2620:0:2d0:200::7"
        matching_ipv4 = create :ip_allowlist_entry, :org, allow_list_value: "8.8.8.0/24"
        assert_same_elements \
          [matching_ipv4],
          IpAllowlistEntry.matching_ip(ip).all
      end

      test "does not raise query warning when passed invalid IP value" do
        create :ip_allowlist_entry, :org, allow_list_value: "1.1.1.0/24"
        assert_no_query_warnings do
          assert_empty IpAllowlistEntry.matching_ip("blah").all
        end
      end

      test "does not raise query warning when passed IPv4 CIDR with network mask" do
        create :ip_allowlist_entry, :org, allow_list_value: "1.1.1.0/24"
        assert_no_query_warnings do
          assert_empty IpAllowlistEntry.matching_ip("1.1.1.0/24").all
        end
      end

      test "does not raise query warning when passed IPv6 CIDR with network mask" do
        create :ip_allowlist_entry, :org, allow_list_value: "2001:db8::/48"
        assert_no_query_warnings do
          assert_empty IpAllowlistEntry.matching_ip("2001:db8::/48").all
        end
      end

      test "does not raise query warning when passed IPv6 CIDR with zone ID" do
        create :ip_allowlist_entry, :org, allow_list_value: "fe80::3%eth0"
        assert_no_query_warnings do
          assert_empty IpAllowlistEntry.matching_ip("fe80::3%eth0").all
        end
      end
    end

    context "#for_query" do
      test "returns scoped entries when query is blank" do
        entry = create :ip_allowlist_entry, owner: @business
        assert_equal [entry], @business.ip_allowlist_entries.for_query("  ")
        assert_equal [entry], @business.ip_allowlist_entries.for_query(nil)
      end

      test "returns entries matching allow list value on enterprise" do
        matching = create :ip_allowlist_entry, owner: @business, name: "matching", allow_list_value: "1.2.3.4"
        not_matching = create :ip_allowlist_entry, owner: @business, name: "not matching", allow_list_value: "5.6.7.8"
        assert_equal [matching], @business.ip_allowlist_entries.for_query("1.2.3")
      end

      test "returns entries matching name on enterprise" do
        matching = create :ip_allowlist_entry, owner: @business, name: "very matching", allow_list_value: "1.2.3.4"
        not_matching = create :ip_allowlist_entry, owner: @business, name: "not matching", allow_list_value: "5.6.7.8"
        assert_equal [matching], @business.ip_allowlist_entries.for_query("very")
      end

      test "returns entries matching both name and allow list value on enterprise" do
        matching = create :ip_allowlist_entry, owner: @business, name: "very matching", allow_list_value: "123.123.123.123"
        also_matching = create :ip_allowlist_entry, owner: @business, name: "12345", allow_list_value: "8.8.8.8"
        not_matching = create :ip_allowlist_entry, owner: @business, name: "not matching", allow_list_value: "5.6.7.8"
        assert_same_elements \
          [matching, also_matching],
          @business.ip_allowlist_entries.for_query("123")
      end

      test "returns entries matching allow list value on org" do
        org = create :business_plus_org
        matching = create :ip_allowlist_entry, owner: org, name: "matching", allow_list_value: "1.2.3.4"
        not_matching = create :ip_allowlist_entry, owner: org, name: "not matching", allow_list_value: "5.6.7.8"
        assert_equal [matching], org.ip_allowlist_entries.for_query("1.2.3")
      end

      test "returns entries matching name on org" do
        org = create :business_plus_org
        matching = create :ip_allowlist_entry, owner: org, name: "very matching", allow_list_value: "1.2.3.4"
        not_matching = create :ip_allowlist_entry, owner: org, name: "not matching", allow_list_value: "5.6.7.8"
        assert_equal [matching], org.ip_allowlist_entries.for_query("very")
      end

      test "returns entries matching both name and allow list value on org" do
        org = create :business_plus_org
        matching = create :ip_allowlist_entry, owner: org, name: "very matching", allow_list_value: "123.123.123.123"
        also_matching = create :ip_allowlist_entry, owner: org, name: "12345", allow_list_value: "8.8.8.8"
        not_matching = create :ip_allowlist_entry, owner: org, name: "not matching", allow_list_value: "5.6.7.8"
        assert_same_elements \
          [matching, also_matching],
          org.ip_allowlist_entries.for_query("123")
      end
    end

    context "#owner_name_and_type" do
      test "returns name and type when owner is Business" do
        entry = create :ip_allowlist_entry, owner: @business
        assert_equal "#{entry.owner.name} enterprise", entry.owner_name_and_type
      end

      test "returns name and type when owner is Organization" do
        org = create :business_plus_org, login: "fender"
        org.create_profile name: "Fender Musical Instruments Corporation"
        entry = create :ip_allowlist_entry, owner: org
        assert_equal "#{entry.owner.safe_profile_name} organization", entry.owner_name_and_type
      end

      test "returns name of app and type when owner is Integration" do
        entry = create :ip_allowlist_entry, :integration
        assert_equal "#{entry.owner.name} GitHub App", entry.owner_name_and_type
      end
    end

    context "#includes?" do
      test "returns true when an IP allow list entry in CIDR notation includes an IPv4 address" do
        entry  = create :ip_allowlist_entry, allow_list_value: "192.168.100.0/22"
        assert entry.includes?("192.168.100.22")
      end

      test "returns true when an IP allow list entry without CIDR notation includes an IPv4 address" do
        entry  = create :ip_allowlist_entry, allow_list_value: "192.168.100.22"
        assert entry.includes?("192.168.100.22")
      end

      test "returns false when an IP allow list entry excludes an IPv4 address" do
        entry  = create :ip_allowlist_entry, allow_list_value: "192.168.100.0/22"
        refute entry.includes?("192.168.0.1")
      end

      test "returns true when an IP allow list entry in CIDR notation includes an IPv6 address" do
        entry  = create :ip_allowlist_entry, allow_list_value: "2001:db8::/48"
        assert entry.includes?("2001:db8:0:ffff:ffff:ffff:ffff:bf66")
      end

      test "returns true when an IP allow list entry without CIDR notation includes an IPv6 address" do
        entry  = create :ip_allowlist_entry, allow_list_value: "2620:0:2d0:200::7"
        assert entry.includes?("2620:0:2d0:200::7")
      end

      test "returns false when an IP allow list entry excludes an IPv6 address" do
        entry  = create :ip_allowlist_entry, allow_list_value: "2001:db8::/48"
        refute entry.includes?("2620:0:2d0:200::7")
      end

      test "returns false when argument is invalid IP address" do
        entry = create :ip_allowlist_entry, allow_list_value: "2001:db8::/48"
        refute entry.includes?("whatever")
      end

      test "returns false when allow_list_value is invalid IP address" do
        entry = build :ip_allowlist_entry, allow_list_value: "whatever"
        refute entry.includes?("2620:0:2d0:200::7")
      end
    end

    context "::eligible_for_ip_allowlist?" do
      test "returns true for Business" do
        assert IpAllowlistEntry.eligible_for_ip_allowlist?(@business)
      end

      test "returns true for Organization owned by Business" do
        org = if GitHub.enterprise?
          create :organization, plan: GitHub::Plan::ENTERPRISE
        else
          create :organization
        end
        @business.add_organization org
        org.reload
        assert IpAllowlistEntry.eligible_for_ip_allowlist?(org)
      end

      test "returns true for Organization with business_plus plan" do
        assert IpAllowlistEntry.eligible_for_ip_allowlist?(create(:business_plus_org))
      end

      test "returns false for Organization without business_plus plan" do
        org = create :organization, plan: GitHub::Plan::BUSINESS
        refute IpAllowlistEntry.eligible_for_ip_allowlist?(org)
      end

      test "returns true for Integration" do
        assert IpAllowlistEntry.eligible_for_ip_allowlist?(create(:integration))
      end
    end

    context "#owner_eligible_for_ip_allowlist?" do
      test "returns true when owner is Business" do
        entry = create :ip_allowlist_entry, :business
        assert_predicate entry, :owner_eligible_for_ip_allowlist?
      end

      test "returns true when owner is Organization owned by Business" do
        org = if GitHub.enterprise?
          create :organization, plan: GitHub::Plan::ENTERPRISE
        else
          create :organization
        end
        @business.add_organization org
        org.reload
        entry = create :ip_allowlist_entry, owner: org
        assert_predicate entry, :owner_eligible_for_ip_allowlist?
      end

      test "returns true when owner is Organization with business_plus plan" do
        entry = create :ip_allowlist_entry, owner: create(:business_plus_org)
        assert_predicate entry, :owner_eligible_for_ip_allowlist?
      end

      test "returns false for Organization without business_plus plan" do
        entry = build :ip_allowlist_entry, owner: create(:organization, plan: GitHub::Plan::BUSINESS)
        refute_predicate entry, :owner_eligible_for_ip_allowlist?
      end

      test "returns true when owner is Integration" do
        entry = create :ip_allowlist_entry, :integration
        assert_predicate entry, :owner_eligible_for_ip_allowlist?
      end
    end

    context "::ip_included_in_entries?" do
      test "returns false if ip or entries arguments are blank" do
        refute IpAllowlistEntry.ip_included_in_entries? ip: "1.1.1.1", entries: []
        refute IpAllowlistEntry.ip_included_in_entries? ip: "", entries: [create(:ip_allowlist_entry)]
      end

      test "returns true when IP is included in entries" do
        owner = create :business_plus_org
        entries = [
          create(:ip_allowlist_entry, owner: owner, allow_list_value: "192.168.100.0/22"),
          create(:ip_allowlist_entry, owner: owner, allow_list_value: "8.8.8.8"),
        ]
        assert IpAllowlistEntry.ip_included_in_entries? ip: "192.168.100.32", entries: entries
      end

      test "returns false when IP is not included in entries" do
        owner = create :business_plus_org
        entries = [
          create(:ip_allowlist_entry, owner: owner, allow_list_value: "192.168.100.0/22"),
          create(:ip_allowlist_entry, owner: owner, allow_list_value: "8.8.8.8"),
        ]
        refute IpAllowlistEntry.ip_included_in_entries? ip: "1.1.1.1", entries: entries
      end
    end

    context "SQL queries using BETWEEN range_from AND range_to" do
      test "can successfully query for IPv4 between range_from and range_to" do
        ip = "192.168.100.110"
        cidr = "192.168.100.0/22"
        entry = create :ip_allowlist_entry, :business, allow_list_value: cidr

        result = IpAllowlistEntry
          .where(owner_id: entry.owner_id, owner_type: entry.owner_type, active: true)
          .where("INET6_ATON(?) BETWEEN range_from AND range_to", ip)
          .pick(:allow_list_value)

        assert_equal cidr, result
      end

      test "fails to find IPv4 not between range_from and range_to" do
        ip = "200.200.200.110"
        cidr = "192.168.100.0/22"
        entry = create :ip_allowlist_entry, :business, allow_list_value: cidr

        results = IpAllowlistEntry
          .where(owner_id: entry.owner_id, owner_type: entry.owner_type, active: true)
          .where("INET6_ATON(?) BETWEEN range_from AND range_to", ip)
          .pluck(:allow_list_value)
        assert_empty results
      end

      test "can successfully query for IPv6 between range_from and range_to" do
        ip = "2001:0db8:0000:0000:0000:0000:0000:0000"
        cidr = "2001:db8::/48"
        entry = create :ip_allowlist_entry, :business, allow_list_value: cidr
        result = IpAllowlistEntry
          .where(owner_id: entry.owner_id, owner_type: entry.owner_type, active: true)
          .where("INET6_ATON(?) BETWEEN range_from AND range_to", ip)
          .pick(:allow_list_value)

        assert_equal cidr, result
      end

      test "fails to find IPv6 not between range_from and range_to" do
        ip = "2100:0db8:0000:0000:0000:0000:0000:0000"
        cidr = "2001:db8::/48"
        entry = create :ip_allowlist_entry, :business, allow_list_value: cidr
        results = IpAllowlistEntry
          .where(owner_id: entry.owner_id, owner_type: entry.owner_type, active: true)
          .where("INET6_ATON(?) BETWEEN range_from AND range_to", ip)
          .pluck(:allow_list_value)
        assert_empty results
      end
    end

    context "instrumentation" do
      [:business, :org, :integration].each do |owner_type|
        test "instruments creation when owner is #{owner_type}" do
          events = subscribe "ip_allow_list_entry.create"

          entry = create :ip_allowlist_entry, owner_type

          expected_payload = {}.tap do |payload|
            payload[:ip_allow_list_entry] = entry.allow_list_value
            payload[:ip_allow_list_entry_id] = entry.id
            payload[:ip_allow_list_entry_name] = entry.name
            payload[:active] = entry.active?
            payload[entry.owner.event_prefix] = entry.owner.to_s
            payload["#{entry.owner.event_prefix}_id".to_sym] = entry.owner.id
            if owner_type == :integration
              payload[entry.owner.owner.event_prefix] = entry.owner.owner.to_s
              payload["#{entry.owner.owner.event_prefix}_id".to_sym] = entry.owner.owner.id
            end
          end

          assert event = events.pop, "ip_allow_list_entry.create event was expected"
          assert events.empty?
          assert_equal expected_payload, event.payload
        end

        test "publishes Hydro message on creation when owner is #{owner_type}" do
          actor = create :user
          GitHub.context.push actor_id: actor.id
          entry = create :ip_allowlist_entry, owner_type

          assert_hydro_published({
              entry: Hydro::EntitySerializer.ip_allow_list_entry(entry),
              actor: Hydro::EntitySerializer.user(actor),
            },
            schema: "github.ip_allow_list.v0.IpAllowListEntryCreate",
          )
          assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.IpAllowListEntryCreate")
        end

        test "instruments update when owner is #{owner_type}" do
          entry = create :ip_allowlist_entry, owner_type
          events = subscribe "ip_allow_list_entry.update"

          entry.update allow_list_value: "192.168.0.0/24"

          expected_payload = {}.tap do |payload|
            payload[:ip_allow_list_entry] = entry.allow_list_value
            payload[:ip_allow_list_entry_id] = entry.id
            payload[:ip_allow_list_entry_name] = entry.name
            payload[:active] = entry.active?
            payload[entry.owner.event_prefix] = entry.owner.to_s
            payload["#{entry.owner.event_prefix}_id".to_sym] = entry.owner.id
            if owner_type == :integration
              payload[entry.owner.owner.event_prefix] = entry.owner.owner.to_s
              payload["#{entry.owner.owner.event_prefix}_id".to_sym] = entry.owner.owner.id
            end
          end

          assert event = events.pop, "ip_allow_list_entry.update event was expected"
          assert events.empty?
          assert_equal expected_payload, event.payload
        end

        test "publishes Hydro message on update when owner is #{owner_type}" do
          entry = create :ip_allowlist_entry, owner_type
          reset_hydro

          actor = create :user
          GitHub.context.push actor_id: actor.id
          entry.update allow_list_value: "192.168.0.0/24"

          assert_hydro_published({
              entry: Hydro::EntitySerializer.ip_allow_list_entry(entry),
              actor: Hydro::EntitySerializer.user(actor),
            },
            schema: "github.ip_allow_list.v0.IpAllowListEntryUpdate",
          )
          assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.IpAllowListEntryUpdate")
        end

        test "instruments destroy when owner is #{owner_type}" do
          entry = create :ip_allowlist_entry, owner_type
          events = subscribe "ip_allow_list_entry.destroy"

          entry.destroy

          expected_payload = {}.tap do |payload|
            payload[:ip_allow_list_entry] = entry.allow_list_value
            payload[:ip_allow_list_entry_id] = entry.id
            payload[:ip_allow_list_entry_name] = entry.name
            payload[:active] = entry.active?
            payload[entry.owner.event_prefix] = entry.owner.to_s
            payload["#{entry.owner.event_prefix}_id".to_sym] = entry.owner.id
            if owner_type == :integration
              payload[entry.owner.owner.event_prefix] = entry.owner.owner.to_s
              payload["#{entry.owner.owner.event_prefix}_id".to_sym] = entry.owner.owner.id
            end
          end

          assert event = events.pop, "ip_allow_list_entry.destroy event was expected"
          assert events.empty?
          assert_equal expected_payload, event.payload
        end

        test "publishes Hydro message on destroy when owner is #{owner_type}" do
          entry = create :ip_allowlist_entry, owner_type
          reset_hydro

          actor = create :user
          GitHub.context.push actor_id: actor.id
          entry.destroy

          assert_hydro_published({
              entry: Hydro::EntitySerializer.ip_allow_list_entry(entry),
              actor: Hydro::EntitySerializer.user(actor),
            },
            schema: "github.ip_allow_list.v0.IpAllowListEntryDestroy",
          )
          assert_hydro_messages(count: 1, schema: "github.ip_allow_list.v0.IpAllowListEntryDestroy")
        end
      end
    end
  end
end
