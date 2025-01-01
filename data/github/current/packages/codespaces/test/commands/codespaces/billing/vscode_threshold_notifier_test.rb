# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::VscodeThresholdNotifierTest < GitHub::TestCase

  fixtures do
    @codespace = create(:codespace)
    enable_feature_flag(:codespaces_usage_notification_copy_update)
  end


  context "#call" do
    test "sends notification if codespace has met threshold" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
      results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: ["codespaces"])]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::VscsClient.any_instance.expects(:notify_environment)

      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
    end

    test "request is successfully made" do
      FakeVSOServer.reset!

      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
      results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: ["codespaces"])]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)

      request = FakeVSOServer.requests.last
      expected_path = "/api/v1/environments/#{@codespace.guid}/notify"

      assert_equal "POST", request.request_method
      assert_equal expected_path, request.path
    end

    test "does not send a notification if the codespace is not running" do
      @codespace.stubs(:available?).returns(false)

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).never
      Codespaces::VscsClient.any_instance.expects(:notify_environment).never
      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
    end

    test "does not send a notification if the entitlements feature is disabled" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(false)

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).never
      Codespaces::VscsClient.any_instance.expects(:notify_environment).never
      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
    end

    test "does not send a notification if the owner has not met the threshold" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns([])

      Codespaces::VscsClient.any_instance.expects(:notify_environment).never

      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
    end

    test "does not send a notification if the owner is using their overage budget" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)

      # User goes over spending limit threshold
      results = [
        Billing::Notifications::Result.new(value: 80, threshold: 75, tags: [Billing::Notifications::CODESPACES_SPENDING_LIMIT]),
        Billing::Notifications::Result.new(value: 100, threshold: 90, tags: [Billing::Notifications::CODESPACES_PRODUCT])
      ]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::VscsClient.any_instance.expects(:notify_environment).never

      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
    end

    test "Does not send same notification more than once" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
      results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: ["codespaces"])]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::VscsClient.any_instance.expects(:notify_environment).once
      frozen_date = @codespace.billable_owner.current_metered_billing_cycle_starts_at + 1.day

      Timecop.freeze(frozen_date) do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end
      Timecop.freeze(frozen_date + 1.hour) do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end
      Timecop.freeze(frozen_date + 1.day) do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end
    end

    test "Sends the notification if the first request fails" do
      FakeVSOServer.reset!

      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)

      results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: ["codespaces"])]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::VscsClient.any_instance.stubs(:vscs_api).raises(Codespaces::VscsClient::BadResponseError.new("BOOM!", nil, 31))

      assert_raises Codespaces::VscsClient::BadResponseError do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      # Reset
      Codespaces::VscsClient.any_instance.unstub(:vscs_api)

      # Should work the second time
      Codespaces::VscsClient.any_instance.expects(:notify_environment).once
      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
    end

    test "Can send the same notif for different codespaces" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
      results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: ["codespaces"])]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::VscsClient.any_instance.expects(:notify_environment).twice
      frozen_date = @codespace.billable_owner.current_metered_billing_cycle_starts_at + 1.day

      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)

      new_codespace = create(:codespace)
      Codespaces::Billing::VscodeThresholdNotifier.call(codespace: new_codespace, billable_owner: new_codespace.billable_owner)
    end

    test "Can send the same notification after the next billing period starts" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
      results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: ["codespaces"])]

      Billing::Notifications::UsageNotification.any_instance.expects(:threshold_results).at_least_once.returns(results)

      Codespaces::VscsClient.any_instance.expects(:notify_environment).twice
      frozen_date = @codespace.billable_owner.current_metered_billing_cycle_starts_at + 1.day
      frozen_next_billing_date = @codespace.billable_owner.next_metered_billing_cycle_starts_at + 1.hour

      Timecop.freeze(frozen_date) do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end
      Timecop.freeze(frozen_date + 1.day) do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end
      Timecop.freeze(frozen_next_billing_date) do
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end
    end

    context "messages" do
      test "sends correct message when there is a spending limit" do
        user_with_budget = create(:credit_card_user, plan: "pro")
        codespaces_budget = create(:billing_budget, :enforce, :codespaces, owner: user_with_budget, spending_limit_in_subunits: 10000) # $100 limit
        codespace_for_user_with_budget = create(:codespace, owner: user_with_budget, billable_owner: user_with_budget)

        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
        expected_notification = "You've used 90% of included services for GitHub Codespaces compute. You will be billed for usage beyond the included services and it will count towards your spending limit of $100.00."

        compute_results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
        compute_notif = Billing::Notifications::UsageNotification.new(codespace_for_user_with_budget.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, budget_group: :codespaces, results: compute_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        storage_results = []
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)

        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once

        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: codespace_for_user_with_budget.billable_owner)
      end

      test "sends correct message when there is an unlimited spending limit" do
        user_with_budget = create(:credit_card_user, plan: "pro")
        codespaces_budget = create(:billing_budget, :codespaces, owner: user_with_budget)
        Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
        codespaces_budget.set_unlimited_spending

        codespace_for_user_with_budget = create(:codespace, owner: user_with_budget, billable_owner: user_with_budget)

        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
        expected_notification = "You've used 90% of included services for GitHub Codespaces compute. You will be billed for usage beyond the included services. To avoid extra expenses, manage your spending limit."

        compute_results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
        compute_notif = Billing::Notifications::UsageNotification.new(codespace_for_user_with_budget.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, budget_group: :codespaces, results: compute_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        storage_results = []
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)

        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: codespace_for_user_with_budget.guid, message: expected_notification, display_mode: "warning", modal: false).once

        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: codespace_for_user_with_budget, billable_owner: codespace_for_user_with_budget.billable_owner)
      end

      test "sends correct message default notification when no spending limit exists, FF off" do
        disable_feature_flag(:codespaces_usage_notification_copy_update)
        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
        expected_notification = "You've used 90% of included services for GitHub Codespaces compute. Navigate to [github.com/codespaces](https://github.com/codespaces) where you can see a list of your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. For more information see \"[Making the most of your included free Codespaces usage](https://github.com/community/community/discussions/39697)\"."

        compute_results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
        compute_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, results: compute_results)

        storage_results = []
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)

        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once

        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      test "sends correct message default notification when no spending limit exists" do
        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
        expected_notification = "You've used 90% of included services for GitHub Codespaces compute. When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can [export your unpushed work to a branch.](https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch) To see a full list of your usage, obtain a copy of your [usage report](https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage) to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a [codespace](https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace) or [delete prebuilds for a repository.](https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration)"

        compute_results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
        compute_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, results: compute_results)

        storage_results = []
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)

        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once

        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      test "sends correct message when storage threshold is hit, ff off" do
        disable_feature_flag(:codespaces_usage_notification_copy_update)

        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
        expected_notification = "You've used 100% of included services for GitHub Codespaces storage. "\
        "Navigate to [github.com/codespaces](https://github.com/codespaces) where you can see a list of "\
        "your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending "\
        "limit to keep working in Codespaces beyond the included free usage. For more information see "\
        "\"[Making the most of your included free Codespaces usage]"\
        "(https://github.com/community/community/discussions/39697)\". "\
        "Note that due to the exhaustion of storage included usage, new Codespaces Prebuilds are disabled until you " \
        "set up a spending limit or your included usage quota is reset."

        compute_results = []
        compute_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, budget_group: :codespaces, results: compute_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        storage_results = [Billing::Notifications::Result.new(value: 91, threshold: 100, tags: [Billing::Notifications::CODESPACES_STORAGE_PRODUCT])]
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results)

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)

        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      test "sends correct message when storage threshold is hit" do
        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
        expected_notification = "You've used 100% of included services for GitHub Codespaces storage. When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can [export your unpushed work to a branch.](https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch) To see a full list of your usage, obtain a copy of your [usage report](https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage) to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a [codespace](https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace) or [delete prebuilds for a repository.](https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration) Note that due to the exhaustion of storage included usage, new Codespaces Prebuilds are disabled until you set up a spending limit or your included usage quota is reset."
        compute_results = []
        compute_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, budget_group: :codespaces, results: compute_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

        storage_results = [Billing::Notifications::Result.new(value: 91, threshold: 100, tags: [Billing::Notifications::CODESPACES_STORAGE_PRODUCT])]
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results)

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)

        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      test "sends 1 messages when 2 thresholds were hit, FF off" do
        disable_feature_flag(:codespaces_usage_notification_copy_update)
        # Setup
        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)

        compute_results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
        compute_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, results: compute_results)

        storage_results = [Billing::Notifications::Result.new(value: 77, threshold: 75, tags: [Billing::Notifications::CODESPACES_STORAGE_PRODUCT])]
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results)

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)

        # Expectation
        expected_notification = "You've used 90% of included usage for Codespaces compute and 75% of Codespaces storage. Navigate to [github.com/codespaces](https://github.com/codespaces) where you can see a list of your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. For more information see \"[Making the most of your included free Codespaces usage](https://github.com/community/community/discussions/39697)\"."
        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      test "sends 1 messages when 2 thresholds were hit" do
        # Setup
        Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)

        compute_results = [Billing::Notifications::Result.new(value: 95, threshold: 90, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
        compute_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, results: compute_results)

        storage_results = [Billing::Notifications::Result.new(value: 77, threshold: 75, tags: [Billing::Notifications::CODESPACES_STORAGE_PRODUCT])]
        storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results)

        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)
        Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)

        # Expectation
        expected_notification = "You've used 90% of included usage for Codespaces compute and 75% of Codespaces storage. When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can [export your unpushed work to a branch.](https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch) To see a full list of your usage, obtain a copy of your [usage report](https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage) to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a [codespace](https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace) or [delete prebuilds for a repository.](https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration)"
        Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once
        Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: @codespace.billable_owner)
      end

      context "at 100% entitlements usage" do
        test "sends correct message when there is an unlimited spending limit" do
          user_with_budget = create(:credit_card_user, plan: "pro")
          codespaces_budget = create(:billing_budget, :codespaces, owner: user_with_budget)
          Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
          codespaces_budget.set_unlimited_spending

          codespace_for_user_with_budget = create(:codespace, owner: user_with_budget, billable_owner: user_with_budget)

          Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
          expected_notification = "You've used 100% of included services for GitHub Codespaces compute. You will be billed for usage beyond the included services. To avoid extra expenses, manage your spending limit."

          compute_results = [Billing::Notifications::Result.new(value: 100, threshold: 100, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
          compute_notif = Billing::Notifications::UsageNotification.new(codespace_for_user_with_budget.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, budget_group: :codespaces, results: compute_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

          storage_results = []
          storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

          Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)
          Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)

          Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: codespace_for_user_with_budget.guid, message: expected_notification, display_mode: "warning", modal: false).once

          Codespaces::Billing::VscodeThresholdNotifier.call(codespace: codespace_for_user_with_budget, billable_owner: codespace_for_user_with_budget.billable_owner)
        end

        test "sends correct message when there is a spending limit" do
          user_with_budget = create(:credit_card_user, plan: "pro")
          codespaces_budget = create(:billing_budget, :enforce, :codespaces, owner: user_with_budget, spending_limit_in_subunits: 10000) # $100 limit
          codespace_for_user_with_budget = create(:codespace, owner: user_with_budget, billable_owner: user_with_budget)

          Codespaces::Policy.expects(:entitlements_feature_enabled?).at_least_once.returns(true)
          expected_notification = "You've used 100% of included services for GitHub Codespaces compute. You will be billed for usage beyond the included services and it will count towards your spending limit of $100.00."

          compute_results = [Billing::Notifications::Result.new(value: 100, threshold: 100, tags: [Billing::Notifications::CODESPACES_COMPUTE_PRODUCT])]
          compute_notif = Billing::Notifications::UsageNotification.new(codespace_for_user_with_budget.billable_owner, product: ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT, budget_group: :codespaces, results: compute_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

          storage_results = []
          storage_notif = Billing::Notifications::UsageNotification.new(@codespace.billable_owner, product: ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT, results: storage_results, evaluator: Billing::Notifications::Evaluator.new(thresholds: [75, 90]))

          Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_compute_notification).at_least_once.returns(compute_notif)
          Codespaces::Billing::VscodeThresholdNotifier::EntitlementsThresholdNotification.any_instance.expects(:entitlements_storage_notification).at_least_once.returns(storage_notif)

          Codespaces::VscsClient.any_instance.expects(:notify_environment).with(id: @codespace.guid, message: expected_notification, display_mode: "warning", modal: false).once

          Codespaces::Billing::VscodeThresholdNotifier.call(codespace: @codespace, billable_owner: codespace_for_user_with_budget.billable_owner)
        end
      end
    end
  end
end
