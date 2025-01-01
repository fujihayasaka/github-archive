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
      Codespaces::Vscs::PREBUILD_FEATURE_FLAGS.each { |f| disable_feature_flag(f, repository) }
      # Enable non-codespace FF
      enable_feature_flag(:my_feature, repository)

      computed_flags = Codespaces::Vscs.prebuild_feature_flags(repository)
      assert_equal Codespaces::Vscs::PREBUILD_FEATURE_FLAGS.size, computed_flags.size
      # Get all values from hash that are true
      assert_equal [], computed_flags.select { |_, v| v }.keys

      # Enable codespace FFs
      enable_feature_flag(:codespaces_remap_user_namespace, repository)

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
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, user) }
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, org) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, user) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, org) }

      # ENABLE proxying billable_owner flags
      enable_feature_flag(:codespaces_proxy_billable_owner_flags_to_vscs)

      # Enable codespace FFs for user
      enable_feature_flag(:codespaces_detailed_activity_monitor, user)
      enable_feature_flag(:codespaces_developer, user)
      enable_feature_flag(:codespaces_force_push_shutdown_telemetry, user)

      # Enable non-codespace FF for user
      enable_feature_flag(:my_feature, user)

      # Enable codespace FFs for billable_owner
      enable_feature_flag(:codespaces_enforce_image_allow_list_in_agent, org)
      enable_feature_flag(:codespaces_docker_authz_plugin, org)
      enable_feature_flag(:codespaces_enable_gvisor_for_preventing_container_escapes, org)
      enable_feature_flag(:codespaces_host_setup_policy, org)
      enable_feature_flag(:codespaces_salus_beta_customers)

      # Enable non-codespace FF for user
      enable_feature_flag(:something_else, org)

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
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, user) }
      Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, org) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, user) }
      Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| disable_feature_flag(f, org) }

      # DISABLE proxying billable_owner flags
      disable_feature_flag(:codespaces_proxy_billable_owner_flags_to_vscs)

      # Enable codespace FFs for user
      enable_feature_flag(:codespaces_detailed_activity_monitor, user)
      enable_feature_flag(:codespaces_developer, user)

      # Enable non-codespace FF for user
      enable_feature_flag(:my_feature, user)

      # Enable codespace FFs for billable_owner
      enable_feature_flag(:codespaces_enforce_image_allow_list_in_agent, org)
      enable_feature_flag(:codespaces_docker_authz_plugin, org)
      enable_feature_flag(:codespaces_enable_gvisor_for_preventing_container_escapes, org)
      enable_feature_flag(:codespaces_host_setup_policy, org)
      enable_feature_flag(:codespaces_salus_beta_customers)
      enable_feature_flag(:codespaces_using_copilot_workspace_config)
      enable_feature_flag(:copilot_workspace)

      # Enable non-codespace FF for user
      enable_feature_flag(:something_else, org)

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
          enable_feature_flag(:codespaces_proxy_billable_owner_flags_to_vscs)

          disable_feature_flag(:my_user_flag)
          disable_feature_flag(:my_billable_owner_flag)

          # Enabled for user
          enable_feature_flag(:my_duplicate_flag, user)
          disable_feature_flag(:my_duplicate_flag, org)
          computed_flags_user_enabled = Codespaces::Vscs.feature_flags(user, org)
          assert_equal 3, computed_flags_user_enabled.size
          # Get all values from hash that are true
          assert_equal ["myDuplicateFlag"], computed_flags_user_enabled.select { |_, v| v }.keys

          # Disabled for user
          enable_feature_flag(:my_duplicate_flag, org)
          disable_feature_flag(:my_duplicate_flag, user)
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
      enable_feature_flag(:codespaces_default_account_switching_true_in_proxima)
      user = create :user
      enable_feature_flag(:codespaces_vscode_account_switching, user)
      flags = Codespaces::Vscs.feature_flags(user)
      assert flags["vscodeAccountSwitching"]
      disable_feature_flag(:codespaces_vscode_account_switching, user)
      flags = Codespaces::Vscs.feature_flags(user)
      refute flags["vscodeAccountSwitching"]
    end

    test "always true in multi tenant" do
      enable_feature_flag(:codespaces_default_account_switching_true_in_proxima)
      business = create :business
      user = create :user
      on_multi_tenant_enterprise(tenant: business) do
        enable_feature_flag(:codespaces_vscode_account_switching, user)
        flags = Codespaces::Vscs.feature_flags(user)
        assert flags["vscodeAccountSwitching"]
        disable_feature_flag(:codespaces_vscode_account_switching, user)
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
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      enable_feature_flag(:codespaces_force_storage_v2, user)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "sku", billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns true when force enabled on repo" do
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      enable_feature_flag(:codespaces_force_storage_v2, repo)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "sku", billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns true when enabled for sku" do
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      sku_name = "standardLinux32gb"
      enable_feature_flag(:codespaces_force_storage_v2, repo)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: sku_name, billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns false when disabled for sku" do
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      sku_name = "standardLinux32gb"
      enable_feature_flag(:codespaces_force_storage_v2, repo)
      enable_feature_flag(:codespaces_storage_v2_4_core_sku_reject, repo)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: sku_name, billable_owner: billable_owner)
      assert_equal false, actual
    end

    test "use_storage_v2? returns true when passed a billable owner that is a user" do
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      repo = create(:repository)
      user = create(:user)
      billable_owner = user.billable_owner
      enable_feature_flag(:codespaces_force_storage_v2, billable_owner)
      actual = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "standardLinux32gb", billable_owner: billable_owner)
      assert_equal true, actual
    end

    test "use_storage_v2? returns true when passed a billable owner that is a business" do
      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org, from_example: :simple)

      enable_feature_flag(:codespaces_force_storage_v2, enterprise)
      disable_feature_flag(:codespaces_force_storage_v2, org)
      disable_feature_flag(:codespaces_force_storage_v2, org_admin)
      disable_feature_flag(:codespaces_force_storage_v2, org_repo)
      disable_feature_flag(:codespaces_storage_v2_disallowed)
      actual = Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: org_admin, sku_name: "standardLinux32gb", billable_owner: org)
      assert_equal true, actual
    end

    test "use_storage_v2? returns false when passed a billable owner that is a business and not force enabled" do
      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org, from_example: :simple)

      disable_feature_flag(:codespaces_force_storage_v2, org)
      disable_feature_flag(:codespaces_force_storage_v2, org_admin)
      disable_feature_flag(:codespaces_force_storage_v2, org_repo)
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)
      actual = Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: org_admin, sku_name: "standardLinux32gb", billable_owner: org)
      assert_equal false, actual
    end

    test "use_storage_v2? returns false when passed a billable owner that is a null and not force enabled" do
      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org, from_example: :simple)

      disable_feature_flag(:codespaces_force_storage_v2, org)
      disable_feature_flag(:codespaces_force_storage_v2, org_admin)
      disable_feature_flag(:codespaces_force_storage_v2, org_repo)
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)
      actual = Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: org_admin, sku_name: nil, billable_owner: nil)
      assert_equal false, actual
    end

    test "returns true when the org is under percentage-based rollout and the user is in the bucket" do
      disable_feature_flag(:codespaces_force_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      org = create(:organization)
      org_admin = org.admins.first
      org_repo = create(:repository, owner: org)
      user = create(:user)

      enable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout, org)
      enable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets, user)

      assert Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: user, sku_name: nil, billable_owner: org)
    end

    test "returns true when the business is under percentage-based rollout and the user is in the bucket" do
      disable_feature_flag(:codespaces_force_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      enterprise = create(:business)
      org = create(:business_plus_organization, business: enterprise)
      enterprise.add_organization(org)

      org_admin = org.admins.first
      org_repo = create(:repository, owner: org)
      user = create(:user)

      enable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout, enterprise)
      enable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets, user)

      assert Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: user, sku_name: nil, billable_owner: org)
    end

    test "returns false when the org is under percentage-based rollout but the user is not in the bucket" do
      disable_feature_flag(:codespaces_force_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      org = create(:organization)
      org_admin = org.admins.first
      org_repo = create(:repository, owner: org)
      user = create(:user)

      enable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout, org)

      refute Codespaces::Vscs.use_storage_v2?(repo: org_repo, current_user: user, sku_name: nil, billable_owner: org)
    end

    test "return false when the org is onboarded but the repo is disallowed" do
      disable_feature_flag(:codespaces_force_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout)
      disable_feature_flag(:codespaces_use_storage_v2_percentage_based_rollout_buckets)
      disable_feature_flag(:codespaces_storage_v2_disallowed)

      org = create(:organization)
      repo = create(:repository, owner: org)
      user = create(:user)

      enable_feature_flag(:codespaces_force_storage_v2, org)
      enable_feature_flag(:codespaces_storage_v2_disallowed, repo)

      refute Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: "standardLinux32gb", billable_owner: org)
    end
  end

  context "#available_vscs_target_configs" do
    test "returns configs array when user is in codespaces_developer flag" do
      disable_feature_flag(:codespaces_developer)
      user = create(:user)

      enable_feature_flag(:codespaces_developer, user)

      assert Codespaces::Vscs.available_vscs_target_configs(user).any?
    end

    test "returns empty array when user is not in codespaces_developer flag" do
      disable_feature_flag(:codespaces_developer)
      user = create(:user)

      assert_empty Codespaces::Vscs.available_vscs_target_configs(user)
    end
  end
end
