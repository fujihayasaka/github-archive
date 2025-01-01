# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::LinkedSubscriptionsControllerTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)

    @subscriptions = [
      { subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002", display_name: "Normal subscription" },
      { subscription_id: "76f609e4-ce0f-11ed-afa1-0242ac120002", display_name: "Pay as you go" },
      { subscription_id: "invalid-id", display_name: "Pay as you run" },
    ]
  end

  setup do
    Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:has_token?).returns(true)
  end

  context "#update" do
    test "creates a customer and sets the azure subscription id/name on it" do
      @customer.destroy
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=76f609e4-ce0f-11ed-afa1-0242ac120002&confirm_subscription_selection=1"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:notice], "You have successfully added an Azure subscription to your payment information."

      assert_equal @org.reload.customer.azure_subscription_id, "76f609e4-ce0f-11ed-afa1-0242ac120002"
      assert_equal @org.reload.customer.azure_subscription_name, "Pay as you go"
      assert @org.reload.customer.metered_via_azure
    end

    test "sets the azure subscription id/name on customer" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=76f609e4-ce0f-11ed-afa1-0242ac120002&confirm_subscription_selection=1"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:notice], "You have successfully added an Azure subscription to your payment information."

      assert_equal @customer.reload.azure_subscription_id, "76f609e4-ce0f-11ed-afa1-0242ac120002"
      assert_equal @customer.reload.azure_subscription_name, "Pay as you go"
      assert @customer.reload.metered_via_azure
    end

    test "updates the azure subscription id/name on customer" do
      @customer.update(
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "Normal subscription"
      )

      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=76f609e4-ce0f-11ed-afa1-0242ac120002&confirm_subscription_selection=1"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:notice], "You have successfully updated your Azure subscription."

      assert_equal @customer.reload.azure_subscription_id, "76f609e4-ce0f-11ed-afa1-0242ac120002"
      assert_equal @customer.reload.azure_subscription_name, "Pay as you go"
      assert @customer.reload.metered_via_azure
    end

    test "redirects to org billing path with an error when invalid subscription specified" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=666"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:error], "Invalid subscription specified"

      assert_nil @customer.reload.azure_subscription_id, nil
      assert_nil @customer.reload.azure_subscription_name, nil
      refute @customer.reload.metered_via_azure
    end

    test "redirects to org billing path with an error when confirmation checkbox is not checked" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=76f609e4-ce0f-11ed-afa1-0242ac120002&confirm_subscription_selection=0"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:error], "You must confirm the subscription selection before proceeding"

      assert_nil @customer.reload.azure_subscription_id, nil
      assert_nil @customer.reload.azure_subscription_name, nil
      refute @customer.reload.metered_via_azure
    end

    test "redirects to org billing path with an error when there was an error during set" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=invalid-id&confirm_subscription_selection=1"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:error], "There was an issue adding an Azure subscription to your payment information."

      assert_nil @customer.reload.azure_subscription_id, nil
      assert_nil @customer.reload.azure_subscription_name, nil
      refute @customer.reload.metered_via_azure
    end

    test "redirects to org billing path with an error when there was an error during update" do
      @customer.update(
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "Normal subscription"
      )
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
      as @owner
      put "/azure/organization/#{@org.display_login}/linked_subscriptions?selected_subscription_id=invalid-id&confirm_subscription_selection=1"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:error], "There was an updating your current Azure subscription."

      assert_equal @customer.reload.azure_subscription_id, "80e769f2-ce0f-11ed-afa1-0242ac120002"
      assert_equal @customer.reload.azure_subscription_name, "Normal subscription"
    end
  end

  context "#destroy" do
    test "removes the subscription details and redirects to org billing path" do
      @customer.update(
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "Normal subscription"
      )

      as @owner
      delete "/azure/organization/#{@org.display_login}/linked_subscriptions"
      assert_response :redirect
      assert_includes flash[:notice], "Azure subscription was successfully removed."

      assert_nil @customer.reload.azure_subscription_id, nil
      assert_nil @customer.reload.azure_subscription_name, nil
      refute @customer.reload.metered_via_azure
    end

    test "redirects to org billing path with an error message when there was an error during update" do
      @customer.update(
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "Normal subscription"
      )
      Customer.any_instance.stubs(:update).returns(false)

      as @owner
      delete "/azure/organization/#{@org.display_login}/linked_subscriptions"
      assert_response :redirect
      assert_includes flash[:error], "There was an issue removing the Azure subscription from your payment information."

      assert_equal @customer.reload.azure_subscription_id, "80e769f2-ce0f-11ed-afa1-0242ac120002"
      assert_equal @customer.reload.azure_subscription_name, "Normal subscription"
    end

    test "redirects to org billing path with an error message when removing before metered cycle ends" do
      Timecop.freeze do
        @customer.update(
          azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
          azure_subscription_name: "Normal subscription"
        )
        Customer.any_instance.stubs(:update).returns(false)

        Billing::Kv.store.set(@customer.metered_via_azure_key, Time.now.to_s, expires: @org.next_metered_billing_cycle_starts_at)

        as @owner
        delete "/azure/organization/#{@org.display_login}/linked_subscriptions"
        assert_response :redirect
        assert_includes flash[:error], "Azure subscription cannot be removed until your next metered cycle on #{@org.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"

        assert_equal @customer.reload.azure_subscription_id, "80e769f2-ce0f-11ed-afa1-0242ac120002"
        assert_equal @customer.reload.azure_subscription_name, "Normal subscription"
      end
    end
  end
end if GitHub.billing_enabled?
