# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecurityTrialsControllerHttpTest < GitHub::IntegrationTestCase
  include SecretScanning::Features::FeatureFlagHelper
  include HydroTestHelpers

  fixtures do
    @business = create(:billing_plan_subscription, :business_owned).business
    @owner = create(:user)
    @business.add_owner(@owner, actor: nil)
    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
  end

  setup do
    disable_feature_flag(FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS)
  end

  context "POST /enterprises/:slug/settings/billing/advanced_security/trials" do
    if GitHub.single_business_environment?
      test "returns 404 if single business environment" do
        as @owner
        post "/enterprises/#{@business.to_param}/settings/advanced_security/trials"
        assert_response 404
        refute @business.has_active_advanced_security_subscription?
      end
    elsif TestEnv.test_in_multitenancy_mode?
      test "render not found when user is emu" do
        as @owner

        travel_to("2022-05-01") do
          post "/enterprises/#{@business.to_param}/settings/advanced_security/trials"
          assert_response_not_found
          refute @business.has_active_advanced_security_subscription?
        end
      end
    else
      test "can subscribe to advanced security trial when EA active" do
        as @owner
        @org = create(:organization, admins: [@owner])
        @business.add_organization(@org)

        may_1st = GitHub::Billing.date_in_timezone Date.parse("2022-05-01")

        travel_to may_1st do
          @business.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now

          post "/enterprises/#{@business.to_param}/settings/advanced_security/trials"

          assert_response :redirect
          assert @business.has_active_advanced_security_subscription?
          assert_equal "Subscribed to Advanced Security Trial", flash[:success]
          subscription_item = @business.subscription_items.find_by!(product_uuid: @advanced_security_product_uuid)
          assert_equal "GitHub Advanced Security", subscription_item.subscribable.name
          assert_equal "05/31/2022", subscription_item.free_trial_ends_on.strftime("%m/%d/%Y")
          message = {
            category: "business_advanced_security_subscription",
            action: "subscribe_to_trial",
            label: "business_id:#{@business.id}; dual_enterprise_trial:true; trial_days:30",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
        end
      end

      test "subscribe to advanced security trial" do
        as @owner
        @org = create(:organization, admins: [@owner])
        @business.add_organization(@org)

        travel_to("2022-05-01") do
          post "/enterprises/#{@business.to_param}/settings/advanced_security/trials"

          assert_response :redirect
          assert @business.has_active_advanced_security_subscription?
          assert_equal "Subscribed to Advanced Security Trial", flash[:success]
          subscription_item = @business.subscription_items.find_by!(product_uuid: @advanced_security_product_uuid)
          assert_equal "GitHub Advanced Security", subscription_item.subscribable.name
          assert_equal "05/30/2022", subscription_item.free_trial_ends_on.strftime("%m/%d/%Y")
          message = {
            category: "business_advanced_security_subscription",
            action: "subscribe_to_trial",
            label: "business_id:#{@business.id}; dual_enterprise_trial:false; trial_days:30",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
          @business.reload
          assert_equal "true", @business.advanced_security_enabled_type_for_entity
        end
      end

      test "subscribe to advanced security trial creates an unbundled volume trial when FF enabled" do
        enable_feature_flag(FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS)
        as @owner
        @org = create(:organization, admins: [@owner])
        @business.add_organization(@org)
        SecretScanning::BulkEnablementService
          .expects(:enable_all_secret_scanning)
          .once
          .with(@business, @owner)
          .returns(nil)

        travel_to("2022-05-01") do
          post "/enterprises/#{@business.to_param}/settings/advanced_security/trials"

          assert_response :redirect
          assert @business.has_active_advanced_security_subscription?
          assert_equal "Subscribed to Advanced Security Trial", flash[:success]
          subscription_item = @business.subscription_items.find_by!(product_uuid: @advanced_security_product_uuid)
          assert_equal "GitHub Advanced Security", subscription_item.subscribable.name
          assert_equal "05/30/2022", subscription_item.free_trial_ends_on.strftime("%m/%d/%Y")
          message = {
            category: "business_advanced_security_subscription",
            action: "subscribe_to_trial",
            label: "business_id:#{@business.id}; dual_enterprise_trial:false; trial_days:30",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
          @business.reload
          assert_equal "split_volume_all", @business.advanced_security_enabled_type_for_entity
        end
      end

      test "redirects to enterprise page with warning if user is spammy", skip_with_all_emus: true do
        travel_to("2022-05-01") do
          @business.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now
          @owner.update(spammy: true)

          as @owner
          post "/enterprises/#{@business.display_login}/settings/advanced_security/trials"

          assert_response :redirect
          assert_equal ActionController::Base.helpers.strip_tags(TradeControls::Notices.trade_screening_account_spammy), flash[:error]
          assert_redirected_to enterprise_path(@business)
        end
      end

      test "displays a warning and redirects to enterprise payment information when business has invalid trade screening record status" do
        travel_to("2022-05-01") do
          business = create(:business, :with_self_serve_payment, :with_trade_screening_record, owners: [@owner], trial_expires_at: 30.days.from_now)
          business.trade_screening_record.hit_in_review!
          business.stubs(:perform_live_sdn_screening)

          enable_feature_flag(:live_sdn_screening)

          as @owner
          post "/enterprises/#{business.display_login}/settings/advanced_security/trials"

          assert_response :redirect
          assert_redirected_to settings_billing_tab_enterprise_url(tab: :payment_information)
          assert flash[:trade_screening_generic_notice]
        end
      end

      test "subscribe to advanced security trial when there is no org to redirect to" do
        as @owner

        travel_to("2022-05-01") do
          post "/enterprises/#{@business.to_param}/settings/advanced_security/trials"

          assert_response :redirect
          assert @business.has_active_advanced_security_subscription?
          assert_equal "Create an organization to use your new advanced security trial.", flash[:notice]
          subscription_item = @business.subscription_items.find_by!(product_uuid: @advanced_security_product_uuid)
          assert_equal "GitHub Advanced Security", subscription_item.subscribable.name
          assert_equal "05/30/2022", subscription_item.free_trial_ends_on.strftime("%m/%d/%Y")
          message = {
            category: "business_advanced_security_subscription",
            action: "subscribe_to_trial",
            label: "business_id:#{@business.id}; dual_enterprise_trial:false; trial_days:30",
          }
          assert_hydro_published_partial message, schema: "github.analytics.v0.Event"
        end
      end

      test "returns 404 if not eligible for trial" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        business.customer.update!(billing_type: Customer::BILLING_TYPE_INVOICE)
        refute_predicate business, :eligible_for_self_serve_advanced_security_trial?

        as owner
        post "/enterprises/#{business.to_param}/settings/advanced_security/trials"
        assert_response 404
        refute business.has_active_advanced_security_subscription?
      end
    end
  end
end
