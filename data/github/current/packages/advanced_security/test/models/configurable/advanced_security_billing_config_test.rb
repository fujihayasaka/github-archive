# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurityBillingConfigTest < GitHub::TestCase
  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
    @org = create(:organization, :zuora, admin: @user)
    create(:billing_product_uuid, :advanced_security)

    @self_serve_business = create(:billing_plan_subscription, :business_owned).business
    @owner = @self_serve_business.owners.first
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#set_advanced_security_seats_for_entity" do
    test "returns error when setting seats to 0", skip_enterprise: true do
      business = create(:business, :with_self_serve_payment, owners: [@user])
      business.subscribe_to_advanced_security(seats: 17, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      result = business.set_advanced_security_seats_for_entity(seats: 0, actor: @user)
      assert_instance_of Configurable::AdvancedSecurityBillingConfig::SubscriptionQuantityCannotBeZero, result
      assert_incremented_stat "billing.ghas.set_advanced_security_seats_for_entity.error"
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
    end

    test "returns error when there is no subscription", skip_enterprise: true do
      business = create(:business, :with_self_serve_payment, owners: [@user])
      result = business.set_advanced_security_seats_for_entity(seats: 0, actor: @user)
      assert_instance_of Configurable::AdvancedSecurityBillingConfig::SubscriptionNotFoundError, result
      assert_incremented_stat "billing.ghas.set_advanced_security_seats_for_entity.error"
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
    end

    test "returns error when the underlying update fails", skip_enterprise: true do
      Billing::Public::SubscriptionItem.stubs(:update).returns(GitHub::Result.error("boom!"))
      business = create(:business, :with_self_serve_payment, owners: [@user])
      business.subscribe_to_advanced_security(seats: 17, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      result = business.set_advanced_security_seats_for_entity(seats: 18, actor: @user)
      assert_instance_of Configurable::AdvancedSecurityBillingConfig::SubcriptionUpdateError, result
      assert_incremented_stat "billing.ghas.set_advanced_security_seats_for_entity.error"
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, business.advanced_security_enabled_type_for_entity
    end

    test "allows setting ghas seats on enterprise trial business via config when in manual sales trial", skip_enterprise: true do
      # trial Enterprise
      @business.customer.update_attribute(:billing_type, "card")
      @business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      create(:payment_method, customer: @business.customer)

      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

      result = @business.set_advanced_security_seats_for_entity(seats: 18, actor: @user)
      assert_equal true, result
      assert_equal 18, @business.advanced_security_seats_for_entity
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
    end

    test "allows setting seats on enterprise via config when in manual sales trial", skip_enterprise: true do
      @self_serve_business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

      result = @self_serve_business.set_advanced_security_seats_for_entity(seats: 22, actor: @owner)
      assert_equal true, result
      assert_equal 22, @self_serve_business.advanced_security_seats_for_entity
    end
  end

  context "#advanced_security_purchased_for_entity? for business", skip_enterprise: true do
    test "returns true when advanced security key is set to true" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert @business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
    end

    test "returns false when advanced security key is not set" do
      refute @business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
    end

    test "returns false when advanced security key is set to false" do
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      refute @business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
    end

    test "returns false if only advanced security seats is set" do
      @business.set_advanced_security_seats_for_entity(seats: 17, actor: @user)
      refute @business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
    end

    test "returns true when advanced security metered billing key is set to true" do
      @business.customer.azure_subscription_id = SecureRandom.uuid
      @business.mark_advanced_security_as_metered_for_entity(actor: @user)
      assert @business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, @business.advanced_security_enabled_type_for_entity
    end
  end

  context "#advanced_security_purchased_for_entity? for org" do
    test "returns true when advanced security key is set to true" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert @org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @org.advanced_security_enabled_type_for_entity
    end

    test "returns false when advanced security key is not set" do
      refute @org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity
    end

    test "returns false when advanced security key is set to false" do
      @org.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      refute @org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity
    end

    test "returns false if only advanced security seats is set" do
      @org.set_advanced_security_seats_for_entity(seats: 17, actor: @user)
      refute @org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity
    end

    test "returns false for an org even if true on associated business" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

      @org.business = @business
      @org = @org.reload

      assert @business.advanced_security_purchased_for_entity?
      refute @org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity
    end
  end

  context "#secret_protection_sku_purchased_for_entity? for business", skip_enterprise: true do
    test "returns true when secret protection is purchased" do
      @business.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      assert @business.secret_protection_sku_purchased_for_entity?
    end

    test "returns true when split metered is purchased" do
      @business.set_customer_to_split_metered_offering(actor: @user)
      assert @business.secret_protection_sku_purchased_for_entity?
    end

    test "returns true when split volume is purchased" do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)
      assert @business.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when nothing is purchased" do
      refute @business.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when advanced security is purchased" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @business.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when advanced security metered is purchased" do
      @business.mark_advanced_security_as_metered_for_entity(actor: @user)
      refute @business.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when code security is purchased" do
      @business.set_customer_to_split_volume_code_security_only(actor: @user)
      refute @business.secret_protection_sku_purchased_for_entity?
    end

    test "purchasing advanced security disables secret protection" do
      @business.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @business.secret_protection_sku_purchased_for_entity?
    end
  end

  context "#secret_protection_sku_purchased_for_entity? for org", skip_enterprise: true do
    test "returns true when secret protection is purchased" do
      @org.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      assert @org.secret_protection_sku_purchased_for_entity?
    end

    test "returns true when split metered is purchased" do
      @org.set_customer_to_split_metered_offering(actor: @user)
      assert @org.secret_protection_sku_purchased_for_entity?
    end

    test "returns true when split volume is purchased" do
      @org.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)
      assert @org.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when nothing is purchased" do
      refute @org.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when advanced security is purchased" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @org.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when advanced security metered is purchased" do
      @org.mark_advanced_security_as_metered_for_entity(actor: @user)
      refute @org.secret_protection_sku_purchased_for_entity?
    end

    test "returns false when code security is purchased" do
      @org.set_customer_to_split_volume_code_security_only(actor: @user)
      refute @org.secret_protection_sku_purchased_for_entity?
    end

    test "purchasing advanced security disables secret protection" do
      @org.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @org.secret_protection_sku_purchased_for_entity?
    end
  end

  context "mark_secret_protection_as_purchased_for_entity_as_volume for business" do
    test "works after split-SKU volume is purchased" do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)
      assert @business.secret_protection_sku_purchased_for_entity?
      @business.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      assert @business.secret_protection_sku_purchased_for_entity?
    end
  end

  context "#advanced_security_metered_for_entity? for business", skip_enterprise: true do
    test "returns false when advanced security purchased via monthly billing" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @business.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
    end

    test "returns true when advanced security metered billing key is set to true" do
      @business.customer.azure_subscription_id = SecureRandom.uuid
      @business.mark_advanced_security_as_metered_for_entity(actor: @user)
      assert @business.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, @business.advanced_security_enabled_type_for_entity

      stub_turboghas_summary(additional_metered_committers: 1)

      hydro_payload = hydro_messages(schema: "advanced_security_billing.v0.BillingToggled").first
      assert_equal(true, hydro_payload[:toggle_state])
      assert_equal(@business.id, hydro_payload[:business][:id])
      assert_equal(@user.id, hydro_payload[:actor][:id])
    end

    test "returns true when split metered billing key is set to true" do
      @business.set_customer_to_split_metered_offering(actor: @user)
      assert_predicate @business, :advanced_security_metered_for_entity?
    end

    test "returns false when secret protection is purchased" do
      @business.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @user)
      refute @business.advanced_security_metered_for_entity?
    end

    test "returns false when split-SKU volume is purchased" do
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)
      refute @business.advanced_security_metered_for_entity?
    end
  end

  context "#advanced_security_metered_for_entity? for org" do
    test "returns false for an org with advanced security" do
      # there is no way to created metered billing for an org
      @business.customer.azure_subscription_id = SecureRandom.uuid
      @business.mark_advanced_security_as_metered_for_entity(actor: @user)
      @org.business = @business
      @org = @org.reload

      assert @business.advanced_security_purchased_for_entity?
      assert @business.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, @business.advanced_security_enabled_type_for_entity
      refute @org.advanced_security_purchased_for_entity?
      refute @org.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity
    end
  end

  context "#advanced_security_seats_for_entity for business" do
    test "returns 0 when advanced security seats not set" do
      assert_equal 0, @business.advanced_security_seats_for_entity
    end

    test "returns value when advanced security seats is set" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @business.set_advanced_security_seats_for_entity(seats: 17, actor: @user)
      assert_equal 17, @business.advanced_security_seats_for_entity
    end

    test "returns value when advanced security seats is set when self-serve", skip_enterprise: true do
      business = create(:business, :with_self_serve_payment, owners: [@user])
      business.subscribe_to_advanced_security(seats: 17, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert_equal 17, business.advanced_security_seats_for_entity
    end

    test "return zero when advanced security purchased but no seats set" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert_equal 0, @business.advanced_security_seats_for_entity
    end

    test "returns zero when advanced security seats set but not purchased" do
      @business.set_advanced_security_seats_for_entity(seats: 17, actor: @user)
      assert_equal 0, @business.advanced_security_seats_for_entity
    end
  end

  context "#advanced_security_seats_for_entity for org" do
    test "returns 0 when advanced security seats not set" do
      assert_equal 0, @org.advanced_security_seats_for_entity
    end

    test "returns value when advanced security seats is set" do
      disable_feature_flag(:ghas_self_serve_orgs)
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @org.set_advanced_security_seats_for_entity(seats: 17, actor: @user)
      assert_equal 17, @org.advanced_security_seats_for_entity
    end

    test "return zero when advanced security purchased but no seats set" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert_equal 0, @org.advanced_security_seats_for_entity
    end

    test "returns zero for an org even if set on associated business" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @business.set_advanced_security_seats_for_entity(seats: 17, actor: @user)

      @org.business = @business
      @org = @org.reload

      assert_equal 17, @business.advanced_security_seats_for_entity
      assert_equal 0, @org.advanced_security_seats_for_entity
    end

    test "returns zero for an org even if set on associated business when self-serve", skip_enterprise: true do
      business = create(:business, :with_self_serve_payment, owners: [@user])
      business.subscribe_to_advanced_security(seats: 17, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      @org.business = business
      @org = @org.reload

      assert_equal 17, business.advanced_security_seats_for_entity
      assert_equal 0, @org.advanced_security_seats_for_entity
    end
  end

  context "#advanced_security_purchased_for_entity= for business" do
    test "sets advanced_security_purchased_for_entity to true" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert @business.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity

      hydro_payload = hydro_messages(schema: "advanced_security_billing.v0.BillingToggled").first
      assert_equal(true, hydro_payload[:toggle_state])
      assert_equal(@business.id, hydro_payload[:business][:id])
      assert_equal(@user.id, hydro_payload[:actor][:id])

      hydro_payload = hydro_messages(schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled").first
      assert_equal(true, hydro_payload[:enabled])
      assert_equal(@business.id, hydro_payload[:business_id])
    end

    test "sets advanced_security_purchased_for_entity to false" do
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      refute @business.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity

      hydro_payload = hydro_messages(schema: "advanced_security_billing.v0.BillingToggled").first
      assert_equal(false, hydro_payload[:toggle_state])
      assert_equal(@business.id, hydro_payload[:business][:id])
      assert_equal(@user.id, hydro_payload[:actor][:id])

      hydro_payload = hydro_messages(schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled").first
      assert_equal(false, hydro_payload[:enabled])
      assert_equal(@business.id, hydro_payload[:business_id])
    end

    test "sets advanced_security_purchased_for_entity on new business", skip_enterprise: true do
      business = build(:business)
      refute business.persisted?
      refute business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, business.advanced_security_enabled_type_for_entity
      business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      business.save!
      assert business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, business.advanced_security_enabled_type_for_entity
    end

    test "uses current user as actor when available" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)
      before_count = @business.configuration_entries.count

      @business.mark_advanced_security_as_purchased_for_entity(actor: user)
      @business.reload
      assert @business.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
      assert_equal 1, @business.configuration_entries.count - before_count
      assert_equal user.id, @business.configuration_entries.last.updater_id
    end

    test "uses backup actor when current user not available" do
      user = GitHub.enterprise? ? User.ghost : User.staff_user
      GitHub.context.push(actor_id: nil)
      before_count = @business.configuration_entries.count

      @business.mark_advanced_security_as_purchased_for_entity(actor: user)
      @business.reload
      assert @business.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
      assert_equal 1, @business.configuration_entries.count - before_count
      assert_equal user.id, @business.configuration_entries.last.updater_id
    end
  end

  context "#advanced_security_purchased_for_entity= for org" do
    test "sets advanced_security_purchased_for_entity to true" do
      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      assert @org.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @org.advanced_security_enabled_type_for_entity

      hydro_payload = hydro_messages(schema: "advanced_security_billing.v0.BillingToggled").first
      assert_equal(true, hydro_payload[:toggle_state])
      assert_equal(@org.id, hydro_payload[:organization][:id])
      assert_equal(@user.id, hydro_payload[:actor][:id])

      hydro_payload = hydro_messages(schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled").first
      assert_equal(true, hydro_payload[:enabled])
      assert_equal(@org.id, hydro_payload[:organization_id])
    end

    test "sets advanced_security_purchased_for_entity to false" do
      @org.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      refute @org.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity

      hydro_payload = hydro_messages(schema: "advanced_security_billing.v0.BillingToggled").first
      assert_equal(false, hydro_payload[:toggle_state])
      assert_equal(@org.id, hydro_payload[:organization][:id])
      assert_equal(@user.id, hydro_payload[:actor][:id])

      hydro_payload = hydro_messages(schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled").first
      assert_equal(false, hydro_payload[:enabled])
      assert_equal(@org.id, hydro_payload[:organization_id])
    end

    # An org in GHES would never buy GHAS directly, but the logic should
    # still work correctly in that context
    test "sets advanced_security_purchased_for_entity on new org" do
      org = build(:organization)
      refute org.persisted?
      refute org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, org.advanced_security_enabled_type_for_entity
      org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      org.save!
      assert org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, org.advanced_security_enabled_type_for_entity
    end

    test "uses current user as actor when available" do
      user = create(:user)
      GitHub.context.push(actor_id: user.id)

      @org.mark_advanced_security_as_purchased_for_entity(actor: user)
      assert @org.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @org.advanced_security_enabled_type_for_entity
      assert_equal 1, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY).count
      assert_equal user.id, @org.configuration_entries.find_by(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY).updater_id
    end

    test "uses backup actor when current user not available" do
      user = GitHub.enterprise? ? User.ghost : User.staff_user
      GitHub.context.push(actor_id: nil)

      @org.mark_advanced_security_as_purchased_for_entity(actor: user)
      assert @org.reload.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @org.advanced_security_enabled_type_for_entity
      assert_equal 1, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY).count
      assert_equal user.id, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY).first.updater_id
    end
  end

  context "#advanced_security_seats_for_entity= for business" do
    test "sets advanced_security_seats_for_entity to non-zero" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @business.set_advanced_security_seats_for_entity(actor: @user, seats: 10)
      assert_equal 10, @business.reload.advanced_security_seats_for_entity
    end

    test "sets advanced_security_seats_for_entity to non-zero when self-serve", skip_enterprise: true do
      business = create(:business, :with_self_serve_payment, owners: [@user])
      business.subscribe_to_advanced_security(seats: 10, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert_equal 10, business.reload.advanced_security_seats_for_entity
    end

    test "sets advanced_security_seats_for_entity on new business", skip_enterprise: true do
      business = build(:business, owners: [@user])
      refute business.persisted?
      assert_equal 0, business.advanced_security_seats_for_entity
      business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      business.set_advanced_security_seats_for_entity(actor: @user, seats: 17)
      business.save!
      assert_equal 17, business.advanced_security_seats_for_entity
    end

    test "uses current user as actor when available" do
      user = create(:user)
      @business.add_owner(user, actor: User.ghost)
      GitHub.context.push(actor_id: user.id)
      before_count = @business.configuration_entries.count

      unless @business.advanced_security_seats_stored_on_subscription_item?
        @business.mark_advanced_security_as_purchased_for_entity(actor: user)
        @business.set_advanced_security_seats_for_entity(actor: user, seats: 42)
        assert_equal 42, @business.reload.advanced_security_seats_for_entity
        assert_equal 2, @business.configuration_entries.count - before_count
        assert_equal user.id, @business.configuration_entries.last.updater_id
      end
    end

    test "uses backup actor when current user not available" do
      user = GitHub.enterprise? ? User.ghost : User.staff_user
      GitHub.context.push(actor_id: nil)
      before_count = @business.configuration_entries.count

      unless @business.advanced_security_seats_stored_on_subscription_item?
        @business.mark_advanced_security_as_purchased_for_entity(actor: user)
        @business.set_advanced_security_seats_for_entity(actor: user, seats: 42)
        assert_equal 42, @business.reload.advanced_security_seats_for_entity
        assert_equal 2, @business.configuration_entries.count - before_count
        assert_equal user.id, @business.configuration_entries.last.updater_id
      end
    end
  end

  context "#advanced_security_seats_for_entity= for org" do
    test "sets advanced_security_seats_for_entity to non-zero" do
      disable_feature_flag(:ghas_self_serve_orgs)

      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @org.set_advanced_security_seats_for_entity(actor: @user, seats: 10)
      assert_equal 10, @org.reload.advanced_security_seats_for_entity
    end

    # An org in GHES would never buy GHAS seats directly, but the logic should
    # still work correctly in that context
    test "sets advanced_security_seats_for_entity on new org" do
      org = build(:business_plus_org)
      refute org.persisted?
      assert_equal 0, org.advanced_security_seats_for_entity

      org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      unless org.advanced_security_seats_stored_on_subscription_item?
        org.set_advanced_security_seats_for_entity(actor: @user, seats: 17)
        org.save!
        assert_equal 17, org.advanced_security_seats_for_entity
      end
    end

    test "uses current user as actor when available" do
      disable_feature_flag(:ghas_self_serve_orgs)

      GitHub.context.push(actor_id: @user.id)

      @org.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @org.set_advanced_security_seats_for_entity(actor: @user, seats: 8)
      assert_equal 8, @org.reload.advanced_security_seats_for_entity

      unless @org.advanced_security_seats_stored_on_subscription_item?
        assert_equal 1, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_SEATS_KEY).count
        assert_equal @user.id, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_SEATS_KEY).first.updater_id
      end
    end

    test "uses backup actor when current user not available" do
      disable_feature_flag(:ghas_self_serve_orgs)

      user = GitHub.enterprise? ? User.ghost : User.staff_user
      GitHub.context.push(actor_id: nil)

      @org.mark_advanced_security_as_purchased_for_entity(actor: user)
      @org.set_advanced_security_seats_for_entity(actor: user, seats: 8)
      assert_equal 8, @org.reload.advanced_security_seats_for_entity

      unless @org.advanced_security_seats_stored_on_subscription_item?
        assert_equal 1, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_SEATS_KEY).count
        assert_equal user.id, @org.configuration_entries.where(name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_SEATS_KEY).first.updater_id
      end
    end
  end


  context "#advanced_security_seats_stored_on_subscription_item?" do
    test "true for self-serve Enterprise" do
      assert @self_serve_business.advanced_security_seats_stored_on_subscription_item?
    end

    test "false if GHAS manually enabled on self-serve Enterprise for manual sales trial" do
      # see https://github.com/github/octogrowth/issues/2098#issuecomment-1483219871 for sales flows
      @self_serve_business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      refute @self_serve_business.advanced_security_seats_stored_on_subscription_item?
    end

    test "true if has enterprise has purchased ghas" do
      result = @self_serve_business.subscribe_to_advanced_security(seats: 17, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
      assert @self_serve_business.advanced_security_purchased_for_entity?
      assert @self_serve_business.advanced_security_seats_stored_on_subscription_item?
    end

    test "true if has enterprise has self-serve ghas trial" do
      result = @self_serve_business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
      assert @self_serve_business.advanced_security_purchased_for_entity?
      assert @self_serve_business.advanced_security_seats_stored_on_subscription_item?
    end
  end

  context "#entity_state_blocks_advanced_security?" do
    test "business is considered in a GHAS-blocking state if the business has been downgraded to a free plan" do
      result = @self_serve_business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute @self_serve_business.entity_state_blocks_advanced_security?

      @self_serve_business.downgrade_to_free_plan
      assert_predicate @self_serve_business, :downgraded_to_free_plan?

      assert @self_serve_business.entity_state_blocks_advanced_security?
      refute @self_serve_business.advanced_security_purchased_for_entity?
      assert_equal 0, @self_serve_business.advanced_security_seats_for_entity

    end

    test "business is considered in a GHAS-blocking state if the business has been suspended" do
      result = @self_serve_business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute @self_serve_business.entity_state_blocks_advanced_security?

      @self_serve_business.suspend("Just because")

      assert @self_serve_business.entity_state_blocks_advanced_security?
      refute @self_serve_business.advanced_security_purchased_for_entity?
      assert_equal 0, @self_serve_business.advanced_security_seats_for_entity

    end

    test "business is not considered in a GHAS-blocking state if not suspended and not on a free plan" do
      result = @self_serve_business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute @self_serve_business.entity_state_blocks_advanced_security?
    end
  end

  context "#set_advanced_security_enabled_type_for_entity" do
    test "can enable advanced security for a business by type" do
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)
      assert @business.advanced_security_purchased_for_entity?
      refute @business.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
    end

    test "can enable advanced security for a business by type with metered billing" do
      @business.customer.azure_subscription_id = SecureRandom.uuid
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @user)
      assert @business.advanced_security_purchased_for_entity?
      assert @business.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, @business.advanced_security_enabled_type_for_entity
    end

    test "can disable advanced security for a business by type" do
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: @user)
      refute @business.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
    end

    test "can enable advanced security for a org by type" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)
      assert @org.advanced_security_purchased_for_entity?
      refute @org.advanced_security_metered_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @org.advanced_security_enabled_type_for_entity
    end

    test "can enable advanced security for a org by type with metered billing" do
      @org.customer.azure_subscription_id = SecureRandom.uuid
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @user)
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, @org.advanced_security_enabled_type_for_entity
    end

    test "can disable advanced security for an org by type" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: @user)
      refute @org.advanced_security_purchased_for_entity?
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @org.advanced_security_enabled_type_for_entity
    end

    test "ensure transition to GHAS_VOLUME supports existing enabled repositories" do
      assert_equal Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, @business.advanced_security_enabled_type_for_entity
      @business.config.enable(Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY, @user)
      assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, @business.advanced_security_enabled_type_for_entity
      assert @business.advanced_security_purchased_for_entity?
    end

    test "instruments billing security license events when a secret protection-only volume SKU is purchased" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments billing security license events when a code security-only volume SKU is purchased" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments billing security license events when all volume based split SKUs are purchased" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments billing security license events when a GHAS split metered SKU is purchased" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments billing security license events when a GHAS metered SKU is purchased" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments billing security license events when a GHAS volume SKU is purchased" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: true
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments billing security license events when advanced security is turned off" do
      @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: @user)
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        organization: Hydro::EntitySerializer.organization(@org),
        toggle_state: false
      }, schema: "advanced_security_billing.v0.BillingToggled")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        business: Hydro::EntitySerializer.business(@business),
        toggle_state: false
      }, schema: "advanced_security_billing.v0.BillingToggled")
    end

    test "instruments security overview advanced security license toggled events when a secret protection-only volume SKU is purchased" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: true,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: true,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "instruments security overview advanced security license toggled events when a code security-only volume SKU is purchased" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: true,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: true,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "instruments security overview advanced security license toggled events when all split volume SKUs are purchased" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: true,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: true,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "instruments security overview advanced security license toggled events when a GHAS split metered SKU is purchased" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: true,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: true,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "instruments security overview advanced security license toggled events when a GHAS metered SKU is purchased" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: true,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: true,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "instruments security overview advanced security license toggled events when a GHAS volume SKU is purchased" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: true,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: true,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "instruments security overview advanced security license toggled events when advanced security is turned off" do
      now = Time.now

      Timecop.freeze(now) do
        @org.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: @user)
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: @user)

        assert_hydro_published({
          organization_id: @org.id,
          enabled: false,
          license_toggled_for_org_at: now.utc
        }, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")

        assert_hydro_published({
          business_id: @business.id,
          enabled: false,
          license_toggled_at: now.utc
        }, schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled")
      end
    end

    test "secret_protection_purchased_for_entity" do
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_SPLIT_METERED, actor: @user)
      assert @business.secret_protection_purchased_for_entity?
    end
  end
end if GitHub.billing_enabled?
