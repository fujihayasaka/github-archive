# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class UsageNotifierTest < GitHub::TestCase
    include Billing::Notifications::NotifierTestHelpers

    fixtures do
      @user = create(:credit_card_user, plan: "free")
      @business = create(:business)
      @organization = create(:organization, business: @business)
    end

    setup do
      @content = create(:usage_notification_content, :info, :actions)
      @events = subscribe "billing.metered_usage_email_sent"
      @current_level = THRESHOLDS[INFO_THRESHOLD]
      @product = ACTIONS_PRODUCT
      @within_entitlements = true
      @subject = UsageNotifier
      @budget = @business.budget_for(group: :shared)
    end

    def mock_notification(owner)
      mock_notification = Billing::Notifications::UsageNotification.new(owner)
      mock_notification.stubs(:highest_priority_notification).returns(@content)
      mock_notification.stubs(:active_budget).returns(@budget)

      mock_notification
    end


    context "#notify_if_applicable" do
      test "raises error when send email without product" do
        assert_raises(ArgumentError) { UsageNotifier.new(@user, usage_notification: mock_notification(@user)).notify_if_applicable }
      end

      test "does not send email if no content" do
        refute_email_notification(@user, product: @product)
      end

      test "does not send email if owner is on legacy plan" do
        user = create(:credit_card_user, plan: "bronze")
        refute_email_notification(user, product: @product, usage_notification: mock_notification(user))
      end

      test "does not send email if email has already been sent" do
        notifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user))
        key = notifier.email_identifier(@current_level)
        Billing::Kv.store.set(key, "true")

        refute_email_notification(@user, product: @product, usage_notification: mock_notification(@user))
      end

      test "sends email" do
        assert_email_notification(@user, product: @product, usage_notification: mock_notification(@user))
      end

      test "sends email for invoiced businesses billed through github for entitlements" do
        assert @business.invoiced?
        expected_payload = {
          product: @product,
          threshold_level: @current_level,
          first_day_in_metered_cycle: @business.current_metered_billing_cycle_starts_at.to_date,
          paid_threshold: !@within_entitlements,
          business: @business.slug,
          business_id: @business.id
        }

        assert_email_notification(@business, product: @product, usage_notification: mock_notification(@business), expected_payload: expected_payload)
      end

      test "does not send email to organization for business entitlement email" do
        assert @organization.delegate_billing_to_business?

        if GitHub.flipper[:ghe_spending_limits].enabled?
          refute_email_notification(@organization, product: @product, usage_notification: mock_notification(@organization))
        else
          assert_email_notification(@organization, product: @product, usage_notification: mock_notification(@organization))
        end
      end

      test "sends email to organization and enterprise for business org budget email" do
        assert @organization.delegate_billing_to_business?

        content = create(:usage_notification_content, :info, :actions, :spending_limit)
        budget = @organization.budget_for(group: :shared)
        budget.update!(spending_limit_in_subunits: 100, enforce_spending_limit: true)
        mock_notification = mock_notification(@organization)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        mock_notification.stubs(:active_budget).returns(budget)

        expected_payload = if GitHub.flipper[:ghe_spending_limits].enabled?
          {
            product: "spending-limit",
            threshold_level: @current_level,
            first_day_in_metered_cycle: @organization.current_metered_billing_cycle_starts_at.to_date,
            paid_threshold: true,
            org: @organization.login,
            org_id: @organization.id
          }
        else
          {
            product: "spending-limit",
            threshold_level: @current_level,
            first_day_in_metered_cycle: @organization.current_metered_billing_cycle_starts_at.to_date,
            paid_threshold: true,
            business: @business.slug,
            business_id: @business.id
          }
        end

        assert_email_notification(@organization, product: @product, usage_notification: mock_notification, expected_payload: expected_payload)
      end

      test "sends email to enterprise for business budget email" do
        content = create(:usage_notification_content, :spending_limit)
        mock_notification = mock_notification(@business)
        mock_notification.stubs(:highest_priority_notification).returns(content)

        expected_payload = {
          product: "spending-limit",
          threshold_level: @current_level,
          first_day_in_metered_cycle: @business.current_metered_billing_cycle_starts_at.to_date,
          paid_threshold: true,
          business: @business.slug,
          business_id: @business.id
        }

        assert_email_notification(@business, product: @product, usage_notification: mock_notification, expected_payload: expected_payload)
      end

      test "sends email to enterprise on entitlement" do
        assert_email_notification(@business, product: @product, usage_notification: mock_notification(@business))
      end

      test "doesn't sends email to enterprise if budget disallows notify" do
        @budget.update(notify_spending: false)
        mock_notification = mock_notification(@business)
        mock_notification.stubs(:active_budget).returns(@budget)

        if GitHub.flipper[:ghe_spending_limits].enabled?
          refute_email_notification(@business, product: @product, usage_notification: mock_notification)
        else
          assert_email_notification(@business, product: @product, usage_notification: mock_notification)
        end
      end

      test "sends email for invoiced businesses billed through github for spending limit" do
        assert @business.invoiced?
        create(:billing_budget, :enforce, owner: @business, spending_limit_in_subunits: 100_00)
        content = create(:usage_notification_content, :info, :spending_limit)
        expected_payload = {
          product: "spending-limit",
          threshold_level: @current_level,
          first_day_in_metered_cycle: @business.current_metered_billing_cycle_starts_at.to_date,
          paid_threshold: true,
          business: @business.slug,
          business_id: @business.id
        }


        mock_notification = mock_notification(@business)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@business, product: @product, usage_notification: mock_notification, expected_payload: expected_payload)
      end

      test "sends email for invoiced organizations for entitlements" do
        organization_billing_manager = create(:user)
        @organization = create(:invoiced_organization, plan: "business", admins: [@user])
        @organization.billing.add_manager(organization_billing_manager, actor: @user)

        expected_payload = {
          product: @product,
          threshold_level: @current_level,
          first_day_in_metered_cycle: @organization.current_metered_billing_cycle_starts_at.to_date,
          paid_threshold: !@within_entitlements,
          org: @organization.login,
          org_id: @organization.id
        }

        assert_email_notification(@organization, product: @product, usage_notification: mock_notification(@organization), expected_payload: expected_payload)
      end

      test "sends email for invoiced organizations for spending limit" do
        organization_billing_manager = create(:user)
        @organization = create(:invoiced_organization, plan: "business", admins: [@user])
        @organization.billing.add_manager(organization_billing_manager, actor: @user)
        create(:billing_budget, :enforce, owner: @organization.reload, spending_limit_in_subunits: 100_00)
        content = create(:usage_notification_content, :info, :spending_limit)

        expected_payload = {
          product: "spending-limit",
          threshold_level: @current_level,
          first_day_in_metered_cycle: @organization.current_metered_billing_cycle_starts_at.to_date,
          paid_threshold: true,
          org: @organization.login,
          org_id: @organization.id
        }

        mock_notification = mock_notification(@organization)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@organization, product: @product, usage_notification: mock_notification, expected_payload: expected_payload)
      end

      test "sends email if usage went over threshold, then below threshold, then back over threshold entitlements" do
        content = create(:usage_notification_content, :info)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :warn)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :error)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)

        refute_email_notification(@user, product: @product)

        content = create(:usage_notification_content, :info)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :warn)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :error)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
      end

      test "sends email if usage went over threshold, then below threshold, then back over threshold paid" do
        content = create(:usage_notification_content, :info, :spending_limit)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :warn, :spending_limit)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :error, :spending_limit)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)

        refute_email_notification(@user, product: @product)

        content = create(:usage_notification_content, :info, :spending_limit)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :warn, :spending_limit)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :error, :spending_limit)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
      end

      test "info to info paid" do
        mock_notification = mock_notification(@user)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
        content = create(:usage_notification_content, :info, :spending_limit)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        assert_email_notification(@user, product: @product, usage_notification: mock_notification)
      end

      test "does not send included usage email if disabled" do
        budget = @user.budget_for(group: :shared)
        budget.update(included_usage_notification: false)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:active_budget).returns(budget)

        refute_email_notification(@user, product: @product, usage_notification: mock_notification)
      end

      test "does not send paid usage email if disabled" do
        budget = @user.budget_for(group: :shared)
        budget.update(paid_usage_notification: false)
        content = create(:usage_notification_content, :warn, :spending_limit)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:active_budget).returns(budget)
        mock_notification.stubs(:highest_priority_notification).returns(content)

        refute_email_notification(@user, product: @product, usage_notification: mock_notification)
      end

      test "marks email sent" do
        Timecop.freeze do
          mock_notification = mock_notification(@user)
          notifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification)
          key = notifier.email_identifier(@current_level)

          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            refute Billing::Kv.store.exists(key).value!
            notifier.notify_if_applicable
          end

          assert Billing::Kv.store.exists(key).value!
        end
      end

      test "sends slack notification if owner is invoiced" do
        org = create(:invoiced_org, plan: "business")
        GitHub::Chatterbox.client.expects(:say).once
        assert_email_notification(org, product: @product, usage_notification: mock_notification(org))
      end

      test "does not send slack notification if owner is not invoiced" do
        org = create(:organization, plan: "business")
        assert !org.invoiced?

        GitHub::Chatterbox.client.expects(:say).never
        assert_email_notification(org, product: @product, usage_notification: mock_notification(org))
      end

      test "does not send slack notification if email is not sent" do
        org = create(:invoiced_org, plan: "business")
        GitHub::Chatterbox.client.expects(:say).never
        refute_email_notification(org, product: @product)
      end
    end

    context "#email_sent?" do
      test "returns true if email sent key is set" do
        travel_to "2017-09-15 07:00" do
          key = "actions-info-business-#{@business.id}-#{@business.current_metered_billing_cycle_starts_at.to_date}"
          Billing::Kv.store.set(key, Time.now.to_s)
          notifier = UsageNotifier.new(@business, product: @product)

          assert notifier.email_sent?(key)
        end
      end

      test "returns false if email sent key is not set" do
        travel_to "2017-07-18 07:00" do
          key = "actions-info-business-#{@business.id}-#{@business.current_metered_billing_cycle_starts_at.to_date}"
          notifier = UsageNotifier.new(@user, product: @product)

          refute notifier.email_sent?(key)
        end
      end

      test "returns true if email sent key can not be retrieved" do
        key = "actions-info-business-#{@business.id}-#{@business.current_metered_billing_cycle_starts_at.to_date}"
        notifier = UsageNotifier.new(@user, product: @product)
        result = GitHub::Result.error(GitHub::KV::UnavailableError)
        Billing::Kv.store.stubs(:exists).returns(result)

        assert notifier.email_sent?(key)
      end
    end

    context "#remove_non_current_email_sent_keys" do
      test "deletes non-nil keys" do
        notifier = UsageNotifier.new(@user, product: @product)
        expected = [notifier.email_identifier(LEVEL_INFO), notifier.email_identifier(LEVEL_ERROR), notifier.email_identifier(LEVEL_ERROR)]

        expected.each { |k| notifier.mark_email_sent(k); assert Billing::Kv.store.exists(k).value! }
        notifier.remove_non_current_email_sent_keys
        expected.each { |k| refute Billing::Kv.store.exists(k).value! }
      end

      test "deletes non-LEVEL_INFO keys" do
        notifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user))
        expected = [notifier.email_identifier(nil), notifier.email_identifier(LEVEL_WARN), notifier.email_identifier(LEVEL_ERROR)]

        expected.each { |k| notifier.mark_email_sent(k); assert Billing::Kv.store.exists(k).value! }
        notifier.remove_non_current_email_sent_keys
        expected.each { |k| refute Billing::Kv.store.exists(k).value! }
      end

      test "deletes non-LEVEL_WARN keys" do
        content = create(:usage_notification_content, :warn)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        notifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification)
        expected = [notifier.email_identifier(nil), notifier.email_identifier(LEVEL_INFO), notifier.email_identifier(LEVEL_ERROR)]

        expected.each { |k| notifier.mark_email_sent(k); assert Billing::Kv.store.exists(k).value! }
        notifier.remove_non_current_email_sent_keys
        expected.each { |k| refute Billing::Kv.store.exists(k).value! }
      end

      test "deletes non-LEVEL_ERROR keys" do
        content = create(:usage_notification_content, :error)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        notifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification)
        expected = [notifier.email_identifier(nil), notifier.email_identifier(LEVEL_INFO), notifier.email_identifier(LEVEL_WARN)]


        expected.each { |k| notifier.mark_email_sent(k); assert Billing::Kv.store.exists(k).value! }
        notifier.remove_non_current_email_sent_keys
        expected.each { |k| refute Billing::Kv.store.exists(k).value! }
      end
    end

    context "#email_identifier" do
      test "includes spending-limit scope, level, owner info, and spending limit if not within entitlements" do
        content = create(:usage_notification_content, :info, :spending_limit)
        budget = @user.budget_for(group: :shared)
        budget.update!(
          spending_limit_in_subunits: 100,
          enforce_spending_limit: true,
        )

        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        mock_notification.stubs(:active_budget).returns(budget)
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification).email_identifier(@current_level)

        expected_tokens = [
          "spending-limit",
          "info",
          @user.class.to_s.downcase,
          @user.id,
          @user.current_metered_billing_cycle_starts_at.to_date,
          "shared",
          100
        ]

        assert_equal expected_tokens.compact.join("-"), identifier
      end

      test "includes product scope, level, owner info if budget doesn't exist" do
        budget = @user.budget_for(group: :shared)
        budget.update!(
          spending_limit_in_subunits: 100,
          enforce_spending_limit: true,
        )
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:active_budget).returns(nil)

        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification).email_identifier(@current_level)

        expected_tokens = [
          "actions",
          "info",
          @user.class.to_s.downcase,
          @user.id,
          @user.current_metered_billing_cycle_starts_at.to_date,
        ]

        assert_equal expected_tokens.compact.join("-"), identifier
      end

      test "raises error if product is not provided" do
        assert_raises(ArgumentError) { UsageNotifier.new(@user).email_identifier(@current_level) }
      end

      test "tokens are dash delimited" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        result = identifier.split "-"
        refute_empty result
        refute_equal identifier, result[0]
      end

      test "is all downcase" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        assert_equal identifier.downcase, identifier
      end

      test "notification-title-token matches product name (entitlements)" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal @product, result[0]
      end

      test "notification-title-token matches 'spending-limit' (paid)" do
        content = create(:usage_notification_content, :info, :spending_limit)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal "spending", result[0]
        assert_equal "limit", result[1]
      end

      test "notification-title-token is product when content is nil" do
        identifier = UsageNotifier.new(@user, product: @product).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal 7, result.length
        assert_equal @product, result[0]
      end

      test "level-token matches current level" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal @current_level, result[1]
      end

      test "level-token is not present when level is nil" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(nil)

        result = identifier.split "-"
        assert_equal 8, result.length
        assert_equal @content.scope, result[0]
      end

      test "class-token matches owner class" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal @user.class, Object.const_get(result[2]&.titlecase)
      end

      test "id-token matches owner id" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal @user.id, result[3].to_i
      end

      test "date-token matches owner first day in metered cycle" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        expected = @user.current_metered_billing_cycle_starts_at.to_date.to_s.split "-"
        result = identifier.split "-"

        assert_equal  expected[0], result[4]
        assert_equal  expected[1], result[5]
        assert_equal  expected[2], result[6]
      end

      test "product-token and spending-limit-token are absent (entitlements)" do
        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification(@user)).email_identifier(@current_level)

        result = identifier.split "-"
        assert_equal 9, result.length
      end

      test "product-token matches owner's budget's product (paid)" do
        budget = create(:billing_budget, owner: @user, spending_limit_in_subunits: 25_00)
        content = create(:usage_notification_content, :info, :spending_limit)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        mock_notification.stubs(:active_budget).returns(budget)

        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification).email_identifier(@current_level)

        result = identifier.split "-"

        assert_equal 10, result.length
        assert_equal @user.budget_for(product: @product).product, result[8]
      end

      test "spending-limit-token matches owner's budget's effective spending limit (paid)" do
        budget = create(:billing_budget, owner: @user, spending_limit_in_subunits: 25_00)
        content = create(:usage_notification_content, :info, :spending_limit)
        mock_notification = mock_notification(@user)
        mock_notification.stubs(:highest_priority_notification).returns(content)
        mock_notification.stubs(:active_budget).returns(budget)

        identifier = UsageNotifier.new(@user, product: @product, usage_notification: mock_notification).email_identifier(@current_level)

        result = identifier.split "-"

        assert_equal 10, result.length
        assert_equal @user.budget_for(product: @product).spending_limit_in_subunits, result[9].to_i
      end
    end
  end
end if GitHub.billing_enabled?
