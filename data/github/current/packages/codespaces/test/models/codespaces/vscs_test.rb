# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesVscsTest < GitHub::TestCase
  context "vscs target" do
    test "default vscs target is a name" do
      assert_equal GitHub.codespaces_vscs_environment[:name], Codespaces::Vscs.default_target
    end

    test "default vscs target config is a hash" do
      assert_equal GitHub.codespaces_vscs_environment, Codespaces::Vscs.default_target_config
    end

    test "get config returns a hash" do
      config = Codespaces::Vscs.config_for_target(Codespaces::Vscs.default_target)
      assert_equal GitHub.codespaces_vscs_environment, config
    end

    test "returns expected web_portal_url_format for local" do
      portal_host = Codespaces::Vscs.config_for_target(:local)[:web_portal_url_format] % { name: "test-codespace", second_level_domain: GitHub.codespaces_web_portal_second_level_domain }
      assert_equal "http://test-codespace.github.localhost:3000", portal_host
    end

    test "returns expected web_portal_url_format for local - multi-tenant" do
      business = create :business
      on_multi_tenant_enterprise(tenant: business) do
        portal_host = Codespaces::Vscs.config_for_target(:local)[:web_portal_url_format] % { name: "test-codespace", second_level_domain: GitHub.codespaces_web_portal_second_level_domain }
        assert_equal "http://test-codespace.#{business.slug}.ghe.localhost:3000", portal_host
      end
    end

    test "returns expected web_portal_url_format for production" do
      portal_host = Codespaces::Vscs.config_for_target(:production)[:web_portal_url_format] % { name: "test-codespace", second_level_domain: GitHub.codespaces_web_portal_second_level_domain }
      assert_equal "https://test-codespace.github.dev", portal_host
    end

    test "returns expected web_portal_url_format for production - multi-tenant" do
      business = create :business
      on_multi_tenant_enterprise(tenant: business) do
        portal_host = Codespaces::Vscs.config_for_target(:production)[:web_portal_url_format] % { name: "test-codespace", second_level_domain: GitHub.codespaces_web_portal_second_level_domain }
        assert_equal "https://test-codespace.#{business.slug}.ghe.dev", portal_host
      end
    end

    test "invalid vscs target raises argument error" do
      assert_raises KeyError do
        Codespaces::Vscs.config_for_target(:not_a_valid_vscs_target)
      end
    end
  end

  context "#feature_flags" do
    test "prebuild_feature_flags returns expected flags" do
      repository = create(:repository)

      # Reset
      Codespaces::Vscs::PREBUILD_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(repository) }
      # Enable non-codespace FF
      GitHub.flipper[:my_feature].enable(repository)

      computed_flags = Codespaces::Vscs.prebuild_feature_flags(repository)
      assert_equal Codespaces::Vscs::PREBUILD_FEATURE_FLAGS.size, computed_flags.size
      # Get all values from hash that are true
      assert_equal [], computed_flags.select { |_, v| v }.keys

      # Enable codespace FFs
      GitHub.flipper[:codespaces_remap_user_namespace].enable(repository)

      computed_flags = Codespaces::Vscs.prebuild_feature_flags(repository)
      assert_equal Codespaces::Vscs::PREBUILD_FEATURE_FLAGS.size, computed_flags.size
      # Get all values from hash that are true
      assert_equal %w[remapUserNamespace], computed_flags.select { |_, v| v }.keys.sort

      # Flag able to be converted to JSON
      begin
        json = GitHub::JSON.encode(computed_flags)
        JSON.parse(json)
        assert true
      rescue JSON::ParserError
        assert false, "JSON encoding or decoding for the flags failed"
      end
    end

    test "returns expected flags enabling 'codespaces_proxy_billable_owner_flags_to_vscs'" do
      user = create(:user)
      org = create(:business_plus_organization)
      # Reset
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(user) }
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(org) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(user) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(org) }

      # ENABLE proxying billable_owner flags
      GitHub.flipper[:codespaces_proxy_billable_owner_flags_to_vscs].enable

      # Enable codespace FFs for user
      GitHub.flipper[:codespaces_detailed_activity_monitor].enable(user)
      GitHub.flipper[:codespaces_developer].enable(user)
      GitHub.flipper[:codespaces_force_push_shutdown_telemetry].enable(user)

      # Enable non-codespace FF for user
      GitHub.flipper[:my_feature].enable(user)

      # Enable codespace FFs for billable_owner
      GitHub.flipper[:codespaces_enforce_image_allow_list_in_agent].enable(org)
      GitHub.flipper[:codespaces_docker_authz_plugin].enable(org)
      GitHub.flipper[:codespaces_enable_gvisor_for_preventing_container_escapes].enable(org)
      GitHub.flipper[:codespaces_host_setup_policy].enable(org)
      GitHub.flipper[:codespaces_salus_beta_customers].enable

      # Enable non-codespace FF for user
      GitHub.flipper[:something_else].enable(org)

      computed_flags_1 = Codespaces::Vscs.feature_flags(user)
      assert_equal Codespaces::Vscs::OWNER_FEATURE_FLAGS.size, computed_flags_1.size
      # Get all values from hash that are true
      assert_equal %w[detailedActivityMonitor developer forcePushShutdownTelemetry], computed_flags_1.select { |_, v| v }.keys.sort

      computed_flags_2 = Codespaces::Vscs.feature_flags(user, org)
      assert_equal Codespaces::Vscs::OWNER_FEATURE_FLAGS.size + Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.size, computed_flags_2.size
      # Get all values from hash that are true
      assert_equal %w[detailedActivityMonitor developer enforceImageAllowListInAgent dockerAuthzPlugin enableGvisorForPreventingContainerEscapes forcePushShutdownTelemetry].sort, computed_flags_2.select { |_, v| v }.keys.sort
    end

    test "returns expected flags disabling 'codespaces_proxy_billable_owner_flags_to_vscs'" do
      user = create(:user)
      org = create(:business_plus_organization)
      # Reset
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(user) }
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(org) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(user) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(org) }

      # DISABLE proxying billable_owner flags
      GitHub.flipper[:codespaces_proxy_billable_owner_flags_to_vscs].disable

      # Enable codespace FFs for user
      GitHub.flipper[:codespaces_detailed_activity_monitor].enable(user)
      GitHub.flipper[:codespaces_developer].enable(user)

      # Enable non-codespace FF for user
      GitHub.flipper[:my_feature].enable(user)

      # Enable codespace FFs for billable_owner
      GitHub.flipper[:codespaces_enforce_image_allow_list_in_agent].enable(org)
      GitHub.flipper[:codespaces_docker_authz_plugin].enable(org)
      GitHub.flipper[:codespaces_enable_gvisor_for_preventing_container_escapes].enable(org)
      GitHub.flipper[:codespaces_host_setup_policy].enable(org)
      GitHub.flipper[:codespaces_salus_beta_customers].enable
      GitHub.flipper[:codespaces_using_copilot_workspace_config].enable
      GitHub.flipper[:copilot_workspace].enable

      # Enable non-codespace FF for user
      GitHub.flipper[:something_else].enable(org)

      computed_flags_1 = Codespaces::Vscs.feature_flags(user)
      assert_equal Codespaces::Vscs::OWNER_FEATURE_FLAGS.size, computed_flags_1.size
      # Get all values from hash that are true
      assert_equal %w[copilotWorkspace detailedActivityMonitor developer usingCopilotWorkspaceConfig], computed_flags_1.select { |_, v| v }.keys.sort

      # NOTE: Should ignore the provided 'org' with 'codespaces_proxy_billable_owner_flags_to_vscs' disabled
      computed_flags_2 = Codespaces::Vscs.feature_flags(user, org)
      assert_equal Codespaces::Vscs::OWNER_FEATURE_FLAGS.size, computed_flags_2.size
      # Get all values from hash that are true
      assert_equal %w[copilotWorkspace detailedActivityMonitor developer usingCopilotWorkspaceConfig], computed_flags_2.select { |_, v| v }.keys.sort
    end

    test "owner flags take precedence over billable_owner flags" do
      user = create(:user)
      org = create(:business_plus_organization)
      # Stub out Codespaces::Vscs.OWNER_FEATURE_FLAGS and Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS
      Codespaces::Vscs.stub_const(:OWNER_FEATURE_FLAGS, %w[my_duplicate_flag my_user_flag]) do
        Codespaces::Vscs.stub_const(:BILLABLE_OWNER_FEATURE_FLAGS, %w[my_duplicate_flag my_billable_owner_flag]) do

          # ENABLE proxying billable_owner flags
          GitHub.flipper[:codespaces_proxy_billable_owner_flags_to_vscs].enable

          GitHub.flipper[:my_user_flag].disable
          GitHub.flipper[:my_billable_owner_flag].disable

          # Enabled for user
          GitHub.flipper[:my_duplicate_flag].enable(user)
          GitHub.flipper[:my_duplicate_flag].disable(org)
          computed_flags_user_enabled = Codespaces::Vscs.feature_flags(user, org)
          assert_equal 3, computed_flags_user_enabled.size
          # Get all values from hash that are true
          assert_equal ["myDuplicateFlag"], computed_flags_user_enabled.select { |_, v| v }.keys

          # Disabled for user
          GitHub.flipper[:my_duplicate_flag].enable(org)
          GitHub.flipper[:my_duplicate_flag].disable(user)
          computed_flags_user_disabled = Codespaces::Vscs.feature_flags(user, org)
          assert_equal 3, computed_flags_user_disabled.size
          # Get all values from hash that are true
          assert_equal [], computed_flags_user_disabled.select { |_, v| v }.keys

        end
      end
    end
  end

  context "vscodeAccountSwitching in .feature_flags " do
    test "depends on flag in dotcom" do
      GitHub.flipper[:codespaces_default_account_switching_true_in_proxima].enable
      user = create :user
      GitHub.flipper[:codespaces_vscode_account_switching].enable(user)
      flags = Codespaces::Vscs.feature_flags(user)
      assert flags["vscodeAccountSwitching"]
      GitHub.flipper[:codespaces_vscode_account_switching].disable(user)
      flags = Codespaces::Vscs.feature_flags(user)
      refute flags["vscodeAccountSwitching"]
    end

    test "always true in multi tenant" do
      GitHub.flipper[:codespaces_default_account_switching_true_in_proxima].enable
      business = create :business
      user = create :user
      on_multi_tenant_enterprise(tenant: business) do
        GitHub.flipper[:codespaces_vscode_account_switching].enable(user)
        flags = Codespaces::Vscs.feature_flags(user)
        assert flags["vscodeAccountSwitching"]
        GitHub.flipper[:codespaces_vscode_account_switching].disable(user)
        flags = Codespaces::Vscs.feature_flags(user)
        assert flags["vscodeAccountSwitching"]
      end
    end
  end

  context ".dev_tunnels_domain_for_target" do
    test "matches correct domain on dotcom production" do
      vscs_target = :production
      dev_tunnels_domain = Codespaces::Vscs.dev_tunnels_domain_for_target(vscs_target)
      assert_equal dev_tunnels_domain, "app.github.dev"
    end

    test "uses dedicated domain on multi tenant with prod target" do
      business = create :business
      vscs_target = :production

      on_multi_tenant_enterprise(tenant: business) do
        dev_tunnels_domain = Codespaces::Vscs.dev_tunnels_domain_for_target(vscs_target)
        assert_equal dev_tunnels_domain, "app.#{business.name}.ghe.dev"
      end
    end

    test "uses dedicated domain on multi tenant with ppe target" do
      business = create :business
      vscs_target = :ppe

      on_multi_tenant_enterprise(tenant: business) do
        dev_tunnels_domain = Codespaces::Vscs.dev_tunnels_domain_for_target(vscs_target)
        assert_equal dev_tunnels_domain, "app.ppe.#{business.name}.ghe.dev"
      end
    end
  end

  context "storage v2 feature flag check" do
    test "use_storage_v2? returns true when force enabled on the user" do
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      GitHub.flipper[:codespaces_force_storage_v2].enable(user)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "sku", billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns true when force enabled on repo" do
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      GitHub.flipper[:codespaces_force_storage_v2].enable(repo)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "sku", billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns true when enabled for sku" do
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      sku_name = "standardLinux32gb"
      GitHub.flipper[:codespaces_force_storage_v2].enable(repo)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: sku_name, billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns false when disabled for sku" do
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      sku_name = "standardLinux32gb"
      GitHub.flipper[:codespaces_force_storage_v2].enable(repo)
      GitHub.flipper[:codespaces_storage_v2_4_core_sku_reject].enable(repo)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: sku_name, billable_owner: billable_owner)
      assert_equal false, actual
    end

    test "use_storage_v2? returns true when passed a billable owner that is a user" do
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      GitHub.flipper[:codespaces_force_storage_v2].enable(billable_owner)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "standardLinux32gb", billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns true when passed a billable owner that is a business" do
      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org, from_example: :simple)

      GitHub.flipper[:codespaces_force_storage_v2].enable(enterprise)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org_admin)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org_repo)
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable
      actual = Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: org_admin, sku_name: "standardLinux32gb", billable_owner: org)
      assert_equal true, actual
    end

    test "use_storage_v2? returns false when passed a billable owner that is a business and not force enabled" do
      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org, from_example: :simple)

      GitHub.flipper[:codespaces_force_storage_v2].disable(org)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org_admin)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org_repo)
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable
      actual = Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: org_admin, sku_name: "standardLinux32gb", billable_owner: org)
      assert_equal false, actual
    end

    test "use_storage_v2? returns false when passed a billable owner that is a null and not force enabled" do
      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org, from_example: :simple)

      GitHub.flipper[:codespaces_force_storage_v2].disable(org)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org_admin)
      GitHub.flipper[:codespaces_force_storage_v2].disable(org_repo)
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable
      actual = Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: org_admin, sku_name: nil, billable_owner: nil)
      assert_equal false, actual
    end

    test "returns true when the org is under percentage-based rollout and the user is in the bucket" do
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      org = create(:organization)
      org_admin = org.admins.first
      org_repo = create(:repository, owner: org)
      user = create(:user)

      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].enable(org)
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].enable(user)

      assert Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: user, sku_name: nil, billable_owner: org)
    end

    test "returns true when the business is under percentage-based rollout and the user is in the bucket" do
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org)
      user = create(:user)

      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].enable(enterprise)
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].enable(user)

      assert Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: user, sku_name: nil, billable_owner: org)
    end

    test "returns false when the org is under percentage-based rollout but the user is not in the bucket" do
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      org = create(:organization)
      org_admin = org.admins.first
      org_repo = create(:repository, owner: org)
      user = create(:user)

      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].enable(org)

      refute Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: user, sku_name: nil, billable_owner: org)
    end

    test "return false when the org is onboarded but the repo is disallowed" do
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable

      org = create(:organization)
      repo = create(:repository, owner: org)
      user = create(:user)

      GitHub.flipper[:codespaces_force_storage_v2].enable(org)
      GitHub.flipper[:codespaces_storage_v2_disallowed].enable(repo)

      refute Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "standardLinux32gb", billable_owner: org)
    end
  end

  context "#available_vscs_target_configs" do
    test "returns configs array when user is in codespaces_developer flag" do
      GitHub.flipper[:codespaces_developer].disable
      user = create(:user)

      GitHub.flipper[:codespaces_developer].enable(user)

      assert Codespaces::Vscs.available_vscs_target_configs(user).any?
    end

    test "returns empty array when user is not in codespaces_developer flag" do
      GitHub.flipper[:codespaces_developer].disable
      user = create(:user)

      assert_empty Codespaces::Vscs.available_vscs_target_configs(user)
    end
  end
end
