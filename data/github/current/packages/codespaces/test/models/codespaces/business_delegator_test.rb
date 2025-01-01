# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesBusinessTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
  end

  setup do
    @codespace_business = Codespaces::BusinessDelegator.new(@business)
  end

  context ".codespaces_enabled_for_all_organizations?" do
    test "defaults to true" do
      assert @codespace_business.codespaces_enabled_for_all_organizations?
    end

    test "true if all entities" do
      policy_group = create(:org_access_policy_group, :all_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      assert @codespace_business.codespaces_enabled_for_all_organizations?
    end

    test "false if selected entities" do
      policy_group = create(:org_access_policy_group, :selected_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      refute @codespace_business.codespaces_enabled_for_all_organizations?
    end

    test "false if none entities" do
      policy_group = create(:org_access_policy_group, :no_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      refute @codespace_business.codespaces_enabled_for_all_organizations?
    end
  end

  context ".codespaces_enabled_for_selected_organizations?" do
    test "defaults to false" do
      refute @codespace_business.codespaces_enabled_for_selected_organizations?
    end

    test "false if all entities" do
      policy_group = create(:org_access_policy_group, :all_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      refute @codespace_business.codespaces_enabled_for_selected_organizations?
    end

    test "true if selected entities" do
      policy_group = create(:org_access_policy_group, :selected_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      assert @codespace_business.codespaces_enabled_for_selected_organizations?
    end

    test "false if none entities" do
      policy_group = create(:org_access_policy_group, :no_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      refute @codespace_business.codespaces_enabled_for_selected_organizations?
    end
  end

  context ".codespaces_disabled?" do
    test "defaults to false" do
      refute @codespace_business.codespaces_disabled?
    end

    test "false if all entities" do
      policy_group = create(:org_access_policy_group, :all_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      refute @codespace_business.codespaces_disabled?
    end

    test "false if selected entities" do
      policy_group = create(:org_access_policy_group, :selected_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      refute @codespace_business.codespaces_disabled?
    end

    test "true if none entities" do
      policy_group = create(:org_access_policy_group, :no_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      assert @codespace_business.codespaces_disabled?
    end
  end

  context ".codespaces_disabled_for_org?" do
    test "returns true if entire business is disabled" do
      @codespace_business.disable_codespaces!
      org = create(:organization)
      @business.add_organization(org)
      assert @codespace_business.codespaces_disabled_for_org?(org)
    end

    test "returns true if org isn't one of the selected enabled" do
      org = create(:organization)
      org_to_enable = create(:organization)
      @business.add_organization(org)
      @business.add_organization(org_to_enable)
      @codespace_business.enable_codespaces_for_selected_organizations!([org_to_enable.id])
      assert @codespace_business.codespaces_disabled_for_org?(org)
    end

    test "returns false if org is one of the selected enabled" do
      org = create(:organization)
      @business.add_organization(org)
      @codespace_business.enable_codespaces_for_selected_organizations!([org.id])
      refute @codespace_business.codespaces_disabled_for_org?(org)
    end
  end

  context ".disable_codespaces!" do
    test "sets the policy constraint to none" do
      @codespace_business.disable_codespaces!
      assert @codespace_business.codespaces_disabled?
    end

    test "sets the policy constraint to none - with previous constraint" do
      policy_group = create(:org_access_policy_group, :selected_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)
      @codespace_business.disable_codespaces!
      assert @codespace_business.codespaces_disabled?
    end
  end

  context ".enable_codespaces_for_all_organizations!" do
    test "sets the policy constraint to all" do
      @codespace_business.enable_codespaces_for_all_organizations!
      assert @codespace_business.codespaces_enabled_for_all_organizations?
    end

    test "sets the policy constraint to all - with previous constraint" do
      policy_group = create(:org_access_policy_group, :selected_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      policy_group.apply_entity_allowlist_membership!([org.id], :organizations)
      @codespace_business.enable_codespaces_for_all_organizations!
      assert @codespace_business.codespaces_enabled_for_all_organizations?
    end
  end

  context ".enable_codespaces_for_selected_organizations!(org_ids)" do
    test "sets the policy constraint to selected" do
      org = create(:organization)
      @business.add_organization(org)
      @codespace_business.enable_codespaces_for_selected_organizations!([org.id])
      assert @codespace_business.codespaces_enabled_for_selected_organizations?
    end

    test "sets the policy constraint to selected - with previous constraint" do
      policy_group = create(:org_access_policy_group, :no_orgs, owner: @business)
      org = create(:organization)
      @business.add_organization(org)
      @codespace_business.enable_codespaces_for_selected_organizations!([org.id])
      assert @codespace_business.codespaces_enabled_for_selected_organizations?
    end

    test "does not wipe out previously enabled organizations" do
      policy_group = create(:org_access_policy_group, :no_orgs, owner: @business)
      org = create(:organization)
      org2 = create(:organization)
      @business.add_organization(org)
      @business.add_organization(org2)
      @codespace_business.enable_codespaces_for_selected_organizations!([org.id])
      @codespace_business.enable_codespaces_for_selected_organizations!([org2.id])
      assert @codespace_business.codespaces_enabled_for_selected_organizations?
      assert_equal 2, @codespace_business.codespaces_enabled_organizations_count
    end
  end

  context ".disable_codespaces_for_selected_organizations!(org_ids)" do
    test "destroys the membership for the given org" do
      disable_feature_flag(:codespaces_allow_trials)
      disable_feature_flag(:codespaces_billing_free)
      org = create(:organization)
      @business.add_organization(org)
      @codespace_business.enable_codespaces_for_selected_organizations!([org.id])
      @codespace_business.disable_codespaces_for_selected_organizations!([org.id])

      refute org.reload.codespaces_feature_enabled?
    end
  end

  context ".codespaces_enabled_organizations_count" do
    test "counts the number of orgs that are currently enabled" do
      assert_equal 0, @codespace_business.codespaces_enabled_organizations_count
      org = create(:organization)
      @business.add_organization(org)
      @codespace_business.enable_codespaces_for_selected_organizations!([org.id])
      assert_equal 1, @codespace_business.codespaces_enabled_organizations_count
    end
  end
end
