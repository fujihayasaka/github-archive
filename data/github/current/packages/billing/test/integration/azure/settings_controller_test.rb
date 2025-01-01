# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::SettingsControllerTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer, metered_via_azure: false, azure_subscription_id: SecureRandom.uuid)
    @org = create(:organization, admin: @owner, customer: @customer)
  end

  context "#update" do
    test "enables metered_via_azure on customer" do
      as @owner

      @customer.metered_via_azure = false
      @customer.save!

      put "/azure/organization/#{@org.display_login}/settings?metered_via_azure=true"

      assert_includes flash[:notice], "Metered billing via Azure successfully updated"
      assert_equal @customer.reload.metered_via_azure, true
    end

    test "disables metered_via_azure on customer" do
      as @owner

      @customer.metered_via_azure = true
      @customer.azure_subscription_id = SecureRandom.uuid
      @customer.save!

      put "/azure/organization/#{@org.display_login}/settings?metered_via_azure=false"

      assert_includes flash[:notice], "Metered billing via Azure successfully updated"
      assert_equal @customer.reload.metered_via_azure, false
    end

    test "redirects with an error when there is no customer" do
      @customer.destroy
      as @owner

      put "/azure/organization/#{@org.display_login}/settings?metered_via_azure=true"

      assert_includes flash[:error], "Unable to update metered via Azure on an organization without a customer"
    end

    test "redirects with an error when there was an error during the update" do
      Customer.any_instance.stubs(:save).returns(false)

      as @owner

      put "/azure/organization/#{@org.display_login}/settings?metered_via_azure=true"

      assert_equal @customer.reload.metered_via_azure, false
      assert_includes flash[:error], "There was an error during the update of metered billing via Azure"
    end

    test "redirects with an error when disabling before metered cycle ends" do
      Timecop.freeze do
        Customer.any_instance.stubs(:save).returns(false)

        as @owner

        @customer.metered_via_azure = true
        @customer.azure_subscription_id = SecureRandom.uuid
        @customer.save!

        Billing::Kv.store.set(@customer.metered_via_azure_key, Time.now.to_s, expires: @org.next_metered_billing_cycle_starts_at)

        put "/azure/organization/#{@org.display_login}/settings?metered_via_azure=false"

        assert_equal @customer.reload.metered_via_azure, true
        assert_includes flash[:error], "Azure subscription cannot be disabled until your next metered cycle on #{@org.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
      end
    end
  end
end if GitHub.billing_enabled?
