# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessAdvancedSecurityDependencyTest < GitHub::TestCase
  include TurboghasHelpers

  fixtures do
    @user = create(:user)
    if GitHub.enterprise?
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
    else
      create(:billing_product_uuid, :advanced_security)
      @business = create(:business, owners: [@user])
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
    end

    # This user contributes to all repos, but isn't a member of any of the orgs
    # and so shouldn't be counted in any of the totals for dotcom.
    @unrelated_user = create :user
  end

  setup do
    @today = Time.zone.today
    GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true) if GitHub.enterprise?
  end

  # Set things up so that enabling_advanced_security_would_exceed_seat_allowance? would return true.
  # This will be a shared starting point for each test of this method.
  def setup_for_enabling_advanced_security_would_exceed_seat_allowance
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @business.set_advanced_security_seats_for_entity(seats: 10, actor: @user)
    end

    @business.advanced_security_license.stubs(:consumed_seats).returns(7)
    @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(5)
  end

  def setup_self_serve_business_for_enabling_advanced_security_would_exceed_seat_allowance
    return if GitHub.enterprise?
    @business = create(:business, :with_self_serve_payment, owners: [@user])
    @business.subscribe_to_advanced_security(seats: 10, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

    @business.advanced_security_license.stubs(:consumed_seats).returns(7)
    @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(5)
  end

  context "#enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?" do
    test "Returns false if GHAS not purchased" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      else
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      end

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns false if unlimited license" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(0)
      else
        @business.set_advanced_security_seats_for_entity(seats: 0, actor: @user)
      end

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns false if seat limit would not be exceeded" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(2)

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns false if consumed seats is at the limit but the new repo uses no extra seats" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @business.advanced_security_license.stubs(:consumed_seats).returns(10)
      @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(0)

      refute @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns true if seat limit would be exceeded" do
      # Deliberately do no other changes beyond what's in the following method.
      # This ensures the changes made in the other tests are doing what we expect
      # and we're not getting spurious test passes.
      setup_for_enabling_advanced_security_would_exceed_seat_allowance
      @business.advanced_security_license.stubs(:seats).returns(10)

      assert @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end

    test "Returns true if seat limit already exceeded" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @business.advanced_security_license.stubs(:consumed_seats).returns(15)
      @business.stubs(:seat_usage_increase_if_advanced_security_enabled_for_all_repos).returns(0)
      @business.advanced_security_license.stubs(:seats).returns(10)

      assert @business.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
    end
  end

  context "advanced_security_configurable?" do
    test "disabled for businesses with GHAS not purchased" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      else
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      end
      refute @business.advanced_security_configurable?
    end

    test "enabled for business repo on dotcom with GHAS purchased", skip_enterprise: true do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert @business.advanced_security_configurable?
    end
  end

  context "#advanced_security_billable_licenses" do
    test "returns total added users for bundled license" do
      stub_turboghas_get_meter_emissions(total: 3)
      assert_equal 3, @business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled)
    end

    test "returns correct count for secret scanning license" do
      stub_turboghas_get_meter_emissions(total: 2, sku: GitHub::Turboghas::SKU::SecretSecurity)
      assert_equal 2, @business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::SecretSecurity)
    end

    test "includes GHES committers in the request when present" do
      ghes_committers = stub(user_ids: [4, 5, 6])
      @business.advanced_security_license.stubs(:ghes_committers).returns(ghes_committers)

      GitHub::Turboghas.client
        .expects(:get_meter_emissions)
        .with(
          has_entries(
            additional_user_ids: [4, 5, 6]
          )
        )
        .returns(
          Twirp::ClientResp.new(
            data: ::Turboghas::Proto::GetMeterEmissionsResponse.new(
              added: [1, 2, 3],
            )
          )
        )

      @business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled)
    end

    test "returns zero when API request fails" do
      GitHub::Turboghas.client
        .stubs(:get_meter_emissions)
        .returns(Twirp::ClientResp.new(error: Twirp::Error.unavailable("Service unavailable")))

      assert_equal 0, @business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled)
    end

    test "returns zero when response is nil" do
      GitHub::Turboghas.client
        .stubs(:get_meter_emissions)
        .returns(nil)
      assert_equal 0, @business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled)
    end
  end

  test "get_advanced_security_orgs_and_counts" do
    org2 = create(:organization, name: "org-b", business: @business)
    org1 = create(:organization, name: "org-a", business: @business)
    create(:organization, name: "org-c", business: @business)

    @business.set_advanced_security_seats_for_entity(actor: @user, seats: 0)

    VCR.use_cassette("get-organizations", persist_with: :turboghas) do |cassette|
      T.cast(cassette.http_interactions, VCR::Cassette::HTTPInteractionList).interactions.each do |interaction|
        body = JSON.parse(interaction.response.body)
        body["organizations"][0]["id"] = org1.id
        body["organizations"][1]["id"] = org2.id
        interaction.response.body = JSON.dump(body)
      end

      res = @business.get_advanced_security_orgs_and_counts(page: 0)
      assert_equal 2, res[:orgs].size
      assert_equal 2, res[:total_orgs_count]
      assert_equal 1, res[:num_orgs_without_ghas]

      assert_equal org1.id, res[:orgs][0][:organization].id
      assert_equal 3, res[:orgs][0][:committer_count]
      assert_equal 2, res[:orgs][0][:unique_committer_count]

      assert_equal org2.id, res[:orgs][1][:organization].id
      assert_equal 1, res[:orgs][1][:committer_count]
      assert_equal 0, res[:orgs][1][:unique_committer_count]
    end
  end

  context "#unbundle_ghas" do
    test "sets bundled volume to unbundled volume", skip_enterprise: true do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

      @business.unbundle_ghas(actor: @user)

      assert_equal @business.advanced_security_enabled_type_for_entity, Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME
    end

    test "sets bundled metered to unbundled metered", skip_enterprise: true do
      @business.mark_advanced_security_as_metered_for_entity(actor: @user)

      @business.unbundle_ghas(actor: @user)

      assert_equal @business.advanced_security_enabled_type_for_entity, Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
    end

    test "raises error if the business doesn't have the right licensing model to be unbundled", skip_enterprise: true do
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)

      assert_raises ArgumentError, "Business does not have the right licensing model for GHAS unbundling" do
        @business.unbundle_ghas(actor: @user)
      end
    end

    test "unbundles enterprise-level security configs" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

      # GHAS enabled config
      ghas_config = create(:security_configuration, :disabled, target: @business)
      ghas_config.enable_ghas = true
      ghas_config.save!

      # GHAS disabled config
      non_ghas_config = create(:security_configuration, :disabled, target: @business)
      non_ghas_config.enable_ghas = false
      non_ghas_config.save!

      @business.unbundle_ghas(actor: @user)

      unbundled_biz_configs = UnbundledSecurityConfiguration.where(target: @business)
      assert_equal 2, unbundled_biz_configs.count

      # If GHAS was enabled, unbundled SKUs are now enabled
      assert T.must(unbundled_biz_configs.first).secret_protection_sku_enabled
      assert T.must(unbundled_biz_configs.first).code_security_sku_enabled

      # If GHAS was disabled, unbundled SKUs are not disabled
      refute T.must(unbundled_biz_configs.second).secret_protection_sku_enabled
      refute T.must(unbundled_biz_configs.second).code_security_sku_enabled
    end

    test "unbundles org-level security configs" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

      org1 = create(:organization, admin: @user, business: @business)
      org2 = create(:organization, admin: @user, business: @business)

      # GHAS enabled config
      ghas_enabled_config = create(:security_configuration, :disabled, target: org1)
      ghas_enabled_config.enable_ghas = true
      ghas_enabled_config.save!

      # GHAS disabled config
      non_ghas_config = create(:security_configuration, :disabled, target: org2)
      non_ghas_config.enable_ghas = false
      non_ghas_config.save!

      @business.unbundle_ghas(actor: @user)

      unbundled_org1_configs = UnbundledSecurityConfiguration.where(target: org1)
      assert_equal 1, unbundled_org1_configs.count

      unbundled_org1_config = unbundled_org1_configs.first

      # If GHAS was enabled, unbundled SKUs are now enabled
      assert T.must(unbundled_org1_config).secret_protection_sku_enabled
      assert T.must(unbundled_org1_config).code_security_sku_enabled

      unbundled_org2_configs = UnbundledSecurityConfiguration.where(target: org2)
      assert_equal 1, unbundled_org2_configs.count

      unbundled_org2_config = unbundled_org2_configs.first

      # If GHAS was disabled, unbundled SKUs are not disabled
      refute T.must(unbundled_org2_config).secret_protection_sku_enabled
      refute T.must(unbundled_org2_config).code_security_sku_enabled
    end

    test "sets up code security service for repos with advanced security service" do
      if GitHub.enterprise?
        GitHub::Enterprise.ensure_business!
        GitHub::Enterprise.license.stubs(:code_security_enabled).returns(true)
      end

      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      org = create(:organization, admin: @user, business: @business)
      repo_ghas_service = create(:private_repository, owner: org)
      Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

      @business.unbundle_ghas(actor: @user)

      assert repo_ghas_service.code_security_enabled?
    end
  end

  context "#rebundle_ghas" do
    test "sets unbundled volume to bundled volume", skip_enterprise: true do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)

      @business.rebundle_ghas(actor: @user)

      assert_equal @business.advanced_security_enabled_type_for_entity, Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME
    end

    test "sets unbundled metered to bundled metered", skip_enterprise: true do
      @business.set_customer_to_split_metered_offering(actor: @user)

      @business.rebundle_ghas(actor: @user)

      assert_equal @business.advanced_security_enabled_type_for_entity, Configurable::AdvancedSecurityBillingConfig::GHAS_METERED
    end

    test "raises error if the business doesn't have the right licensing model to be rebundled", skip_enterprise: true do
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)

      assert_raises ArgumentError, "Business does not have the right licensing model for GHAS rebundling" do
        @business.rebundle_ghas(actor: @user)
      end
    end

    test "rebundles enterprise-level security configs" do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)

      # Both Code Security and Secret Protection enabled
      sp_cs_enabled = create(:unbundled_security_configuration, :disabled, target: @business)
      sp_cs_enabled.code_security_sku_enabled = true
      sp_cs_enabled.secret_protection_sku_enabled = true
      sp_cs_enabled.save!

      # Only Code Security enabled
      cs_only = create(:unbundled_security_configuration, :disabled, target: @business)
      cs_only.secret_protection_sku_enabled = false
      cs_only.code_security_sku_enabled = true
      cs_only.save!

      # Only Secret Protection enabled
      sp_only = create(:unbundled_security_configuration, :disabled, target: @business)
      sp_only.code_security_sku_enabled = false
      sp_only.secret_protection_sku_enabled = true
      sp_only.save!

      # Both Code Security and Secret Protection disabled
      sp_cs_disabled = create(:unbundled_security_configuration, :disabled, target: @business)
      sp_cs_disabled.code_security_sku_enabled = false
      sp_cs_disabled.secret_protection_sku_enabled = false
      sp_cs_disabled.save!

      @business.rebundle_ghas(actor: @user)

      rebundled_biz_configs = SecurityConfiguration.where(target: @business)
      assert_equal 4, rebundled_biz_configs.count

      # If both Code Security and Secret Protection were enabled, GHAS is enabled on rebundling
      assert T.must(rebundled_biz_configs.first).enable_ghas

      # If either one of Code Security or Secret Protection was enabled, GHAS is enabled on rebundling
      assert T.must(rebundled_biz_configs.second).enable_ghas
      assert T.must(rebundled_biz_configs.third).enable_ghas

      # If both Code Security and Secret Protection were disabled, GHAS is disabled
      refute T.must(rebundled_biz_configs.last).enable_ghas

      # After rebundling, unbundled SKUs should be disabled on all configs
      rebundled_biz_configs.each do |config|
        refute T.must(config).code_security_sku_enabled
        refute T.must(config).secret_protection_sku_enabled
      end
    end

    test "rebundles org-level security configs" do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)

      org1 = create(:organization, admin: @user, business: @business)
      org2 = create(:organization, admin: @user, business: @business)
      org3 = create(:organization, admin: @user, business: @business)
      org4 = create(:organization, admin: @user, business: @business)

      # Both Code Security and Secret Protection enabled
      sp_cs_enabled = create(:unbundled_security_configuration, :disabled, target: org1)
      sp_cs_enabled.secret_protection_sku_enabled = true
      sp_cs_enabled.code_security_sku_enabled = true
      sp_cs_enabled.save!

      # Only Code Security enabled
      cs_only = create(:unbundled_security_configuration, :disabled, target: org2)
      cs_only.secret_protection_sku_enabled = false
      cs_only.code_security_sku_enabled = true
      cs_only.save!

      # Only Secret Protection enabled
      sp_only = create(:unbundled_security_configuration, :disabled, target: org3)
      sp_only.code_security_sku_enabled = false
      cs_only.secret_protection_sku_enabled = true
      sp_only.save!

      # Both Code Security and Secret Protection disabled
      sp_cs_disabled = create(:unbundled_security_configuration, :disabled, target: org4)
      sp_cs_disabled.code_security_sku_enabled = false
      sp_cs_disabled.secret_protection_sku_enabled = false
      sp_cs_disabled.save!

      @business.rebundle_ghas(actor: @user)

      rebundling_org1_configs = SecurityConfiguration.where(target: org1)
      assert_equal 1, rebundling_org1_configs.count

      rebundling_org1_config = rebundling_org1_configs.first

      # If both Code Security and Secret Protection were enabled, GHAS is enabled on rebundling
      assert T.must(rebundling_org1_config).enable_ghas

      # If either one of Code Security or Secret Protection was enabled, GHAS is enabled on rebundling
      rebundling_org2_configs = SecurityConfiguration.where(target: org2)
      assert_equal 1, rebundling_org2_configs.count

      rebundling_org2_config = rebundling_org2_configs.first

      assert T.must(rebundling_org2_config).enable_ghas

      rebundling_org3_configs = SecurityConfiguration.where(target: org3)
      assert_equal 1, rebundling_org3_configs.count

      rebundling_org3_config = rebundling_org3_configs.first

      assert T.must(rebundling_org3_config).enable_ghas

      # If both Code Security and Secret Protection were disabled, GHAS is disabled
      rebundling_org4_configs = SecurityConfiguration.where(target: org4)
      assert_equal 1, rebundling_org4_configs.count

      rebundling_org4_config = rebundling_org4_configs.first
      refute T.must(rebundling_org4_config).enable_ghas

      # After rebundling, unbundled SKUs should be disabled on all configs
      [rebundling_org1_config, rebundling_org2_config, rebundling_org3_config, rebundling_org4_config].each do |config|
        refute T.must(config).code_security_sku_enabled
        refute T.must(config).secret_protection_sku_enabled
      end
    end

    test "sets up advanced security service for repos with code security service" do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)
      @business.reload

      org = create(:organization, admin: @user, business: @business)
      repo_code_security_service = create(:private_repository, owner: org)
      Repository.any_instance.stubs(:code_security_enabled?).returns(true)

      @business.rebundle_ghas(actor: @user)

      assert repo_code_security_service.advanced_security_enabled?
    end
  end
end

class ManagedBusinessAdvancedSecurityDependencyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @business = create(:business, :enterprise_managed)
    @owner = @business.owners.first
    # matches cassette
    # must be created with `id`, so that we can lookup the user from the cassette
    User.where(id: [6]).delete_all
    @emu = create(:emu, business: @business, id: 6, login: "emu-6-billable")

    non_emus = 5.times.map { create(:user).id }
  end

  setup do
    if GitHub.enterprise?
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      @business.set_advanced_security_seats_for_entity(actor: @owner, seats: 10)
    end
  end

  context "#get_advanced_security_users_and_counts" do
    test "fetches from turboghas" do
      VCR.use_cassette("get-enterprise-users", persist_with: :turboghas) do
        assert @emu.is_enterprise_managed?
        res = @business.get_advanced_security_enterprise_users_and_counts(actor: @owner, page: 1)
        assert_equal 1, res[:users].size
        assert_equal 1, res[:count]

        assert_equal @emu.id, res[:users][0][:user].id
        assert_equal 1, res[:users][0][:committer_count]
        assert_equal 1, res[:users][0][:unique_committer_count]
      end
    end
  end
end
