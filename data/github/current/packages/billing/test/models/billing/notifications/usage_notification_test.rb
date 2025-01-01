# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class UsageNotificationTest < GitHub::TestCase
    include GitHub::BillingTest
    include ::Billing::ApiTestHelpers
    include ::Billing::ActionsTestHelpers

    fixtures do
      @business = create(:business)
      @org_with_business = create(:organization, business: @business)

      @user = create(:credit_card_user, plan: "free")
      create(:repository, owner: @user)
    end

    setup do
      GitHub.flipper[:codespaces_usage_notification_copy_update].enable
      @evaluator = Evaluator.new(thresholds: [5, 10, 20])
      @product = ACTIONS_PRODUCT
      @results = [Result.new(value: 95, threshold: 90, tags: ["actions"])]

      # set up for budgets, products, skus and entitlements for mock_get_usage_breakdown
      @shared_budget = create(:billing_budget, :shared, :enforce, spending_limit_in_subunits: 100, owner: @business)
      @packages_sku = create_skus_breakdown_hash(
        sku: "default",
        unit_of_measure: "GB",
        unit_price: 0.50,
        entitlement_id: 1,
        entitlement_raw_quantity_consumed: 5,
        overage_quantity_consumed: 2,
        estimated_overage_charge: 100,
        budget_ids: [@shared_budget.id]
      )
      @packages_product = create_product_breakdown_array(name: "packages", skus: [@packages_sku])
      @packages_entitlements = create_entitlement_hash(id: 1, name: "Packages", exhausted: true, allocated_quantity: 5, unit_of_measure: "GB", consumed_quantity: 5)

      @shared_storage_sku = create_skus_breakdown_hash(
        sku: "default",
        entitlement_raw_quantity_consumed: 100 * Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH,
        overage_quantity_consumed: 0,
        entitlement_id: 2,
        unit_of_measure: "Megabytes",
        multiplier: 1,
        estimated_overage_charge: 0,
        unit_price: 0.000000328,
        budget_ids: [@shared_budget.id]
      )

      @shared_storage_product = create_product_breakdown_array(name: "shared storage", skus: [@shared_storage_sku])
      @shared_storage_entitlements = create_entitlement_hash(id: 2, name: "Shared Storage", exhausted: false, allocated_quantity: 512 * Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH, unit_of_measure: "Megabytes", consumed_quantity: 100 * Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH)

      @actions_skus = Billing::Actions::MEUSE_STANDARD_RUNNERS.map do |sku_name|
        create_skus_breakdown_hash(
          sku: sku_name,
          unit_of_measure: "minutes",
          estimated_overage_charge: 0,
          unit_price: 1,
          overage_quantity_consumed: 10,
          entitlement_raw_quantity_consumed: 100,
          entitlement_id: 3,
          budget_ids: [@shared_budget.id]
        )
      end
      @actions_product = create_product_breakdown_array(name: "actions", skus: @actions_skus)
      @actions_entitlements = create_entitlement_hash(id: 3, name: "Actions", allocated_quantity: 300, unit_of_measure: "minutes", consumed_quantity: 300, exhausted: true)
      @product_breakdowns = [
        {
          name: "packages",
          sku_breakdowns: [@packages_sku]
        },
        {
          name: "shared_storage",
          sku_breakdowns: [@shared_storage_sku]
        },
        {
          name: "actions",
          sku_breakdowns: @actions_skus
        }
      ]
    end

    def use_all_actions_minutes
      billable_owner = Billing::MeteredBillingBillableOwnerDesignator.new(@user).billable_owner
      usage_to_add = billable_owner.plan.actions_included_private_minutes

      mock_list_product_usage_response(product: "actions", sku_name: "linux", unit_of_measure: "Hours", quantity: usage_to_add)

      actions_usage = Billing::ActionsUsage.product_usage(@user)
      assert_equal 100, actions_usage.entitlement_minutes_used_percentage
    end

    context "#highest_priority_notification" do
      test "returns nil when evaluator does not have results" do
        assert_empty @evaluator.results

        result = UsageNotification.new(@user, evaluator: @evaluator).highest_priority_notification
        assert_nil result
      end

      test "returns usage notification highest_priority_notification" do
        @evaluator.add_case { 5 }
        refute_empty @evaluator.results

        result = UsageNotification.new(@user, evaluator: @evaluator).highest_priority_notification
        assert_instance_of UsageNotificationContent, result
      end

      test "returns usage notification highest_priority_notification if applicable by default evaluator" do
        mock_get_usage_breakdown_for_actions(standard_skus: true, entitlements_exhausted: true)
        result = UsageNotification.new(@user, product: @product).highest_priority_notification

        assert_instance_of UsageNotificationContent, result
        assert_match result.text, "You've used 100% of included services for GitHub Actions."
        assert_includes result.product_tags, "actions"
      end

      test "returns product-specific formatted highest_priority_notification" do
        @evaluator.add_case { 5 }
        refute_empty @evaluator.results

        result = UsageNotification.new(@user, product: @product, evaluator: @evaluator).highest_priority_notification
        assert_nil result

        @evaluator.add_case(@product) { 10 }
        result = UsageNotification.new(@user, product: @product, evaluator: @evaluator).highest_priority_notification

        assert_instance_of UsageNotificationContent, result
        assert_includes result.filtered_by_tags, @product
      end

      test "returns enterprise-owned-specific copy when owner is organization with enterprise billable_owner" do
        @evaluator.add_case { 5 }
        refute_empty @evaluator.results

        result = UsageNotification.new(@org_with_business, evaluator: @evaluator).highest_priority_notification
        assert_instance_of UsageNotificationContent, result
        assert_match "Your enterprise", result.text
        assert_match "Your enterprise will be billed", result.action_text
      end

      test "returns default copy when owner is enterprise" do
        @evaluator.add_case { 5 }
        refute_empty @evaluator.results

        result = UsageNotification.new(@business, evaluator: @evaluator).highest_priority_notification
        assert_instance_of UsageNotificationContent, result
        assert_match "You've used", result.text
        assert_match "You will be billed", result.action_text
      end

      test "returns nil when user is on a legacy plan" do
        legacy_user = create(:credit_card_user, plan: GitHub::Plan.bronze)
        @evaluator.add_case { 5 }
        refute_empty @evaluator.results

        result = UsageNotification.new(legacy_user, evaluator: @evaluator).highest_priority_notification

        assert_nil result
      end
    end

    context "#active_notifications" do
      test "returns notifications sorted by priority" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["spending_limit"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 77, threshold: 75, tags: ["shared_storage"])
        ]
        active_notifications = UsageNotification.new(@user, results: results).active_notifications
        assert_equal 3, active_notifications.count
      end

      test "groups notifications by threshold" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["spending_limit"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 92, threshold: 90, tags: ["shared_storage"])
        ]
        active_notifications = UsageNotification.new(@user, results: results).active_notifications
        assert_equal 2, active_notifications.count
      end

      test "orders notifications by priority" do
        results = [
          Result.new(value: 82, threshold: 75, tags: ["packages"]),
          Result.new(value: 95, threshold: 90, tags: ["spending_limit"]),
          Result.new(value: 92, threshold: 90, tags: ["shared_storage"])
        ]
        active_notifications = UsageNotification.new(@user, results: results).active_notifications
        assert_equal ["spending_limit"], active_notifications.first.product_tags
        assert_equal ["shared_storage"], active_notifications.second.product_tags
        assert_equal ["packages"], active_notifications.last.product_tags
      end
    end

    context "#owner_budget" do
      test "defaults to shared budget" do
        budget = UsageNotification.new(@user).owner_budget

        assert_equal "shared", budget.product
      end

      test "returns shared budget for shared products" do
        [ACTIONS_PRODUCT, GPR_PRODUCT, SHARED_STORAGE_PRODUCT].each do |product|
          budget = UsageNotification.new(@user, product: product).owner_budget

          assert_equal "shared", budget.product
        end
      end

      test "returns codespaces budget for codespaces product" do
        [CODESPACES_COMPUTE_PRODUCT, CODESPACES_STORAGE_PRODUCT].each do |product|
          budget = UsageNotification.new(@user, product: product).owner_budget

          assert_equal "codespaces", budget.product
        end
      end
    end

    context "#billable_owner_budget" do
      test "defaults to shared budget" do
        budget = UsageNotification.new(@user).billable_owner_budget

        assert_equal "shared", budget.product
      end

      test "returns shared budget for shared products" do
        [ACTIONS_PRODUCT, GPR_PRODUCT, SHARED_STORAGE_PRODUCT].each do |product|
          budget = UsageNotification.new(@user, product: product).billable_owner_budget

          assert_equal "shared", budget.product
        end
      end

      test "returns codespaces budget for codespaces product" do
        [CODESPACES_COMPUTE_PRODUCT, CODESPACES_STORAGE_PRODUCT].each do |product|
          budget = UsageNotification.new(@user, product: product).billable_owner_budget

          assert_equal "codespaces", budget.product
        end
      end
    end

    # Billing::Notifications::Evaluator returns sorted results (see implementation for details)
    # Billing::Notifications::Formatter depends on that behavior (result test fixtures should sorted)
    # These tests will be invalid if the Results fixtures do not match the evaluator's implementation!
    context "text" do
      test "text prefers spending limit over entitlements" do
        results = [
          Result.new(value: 77, threshold: 75, tags: [:spending_limit]),
          Result.new(value: 95, threshold: 90, tags: ["actions"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "You've used 75% of your spending limit for Actions & Packages.", highest_priority_notification.text
      end

      test "text formats included entitlements thresholds" do
        results = [Result.new(value: 95, threshold: 90, tags: ["actions"])]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "You've used 90% of included services for GitHub Actions.", highest_priority_notification.text
      end

      test "text formats all services" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 97, threshold: 90, tags: ["shared_storage"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "You've used 90% of included services for GitHub Actions, Packages, and Storage (GitHub Actions and Packages).", highest_priority_notification.text
      end

      test "text consistently sorts service names" do
        results = [
          Result.new(value: 97, threshold: 90, tags: ["shared_storage"]),
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "You've used 90% of included services for GitHub Actions, Packages, and Storage (GitHub Actions and Packages).", highest_priority_notification.text
      end

      test "text only chooses highest threshold" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 77, threshold: 75, tags: ["shared_storage"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "You've used 90% of included services for GitHub Actions and Packages.", highest_priority_notification.text
      end

      test "text uses enterprise text when billable_owner is an enterprise-owned organization (entitlements)" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 77, threshold: 75, tags: ["shared_storage"])
        ]
        highest_priority_notification = UsageNotification.new(@org_with_business, results: results).highest_priority_notification
        assert_equal "Your enterprise has used 90% of included services for GitHub Actions and Packages.", highest_priority_notification.text
      end

      test "text uses enterprise text when billable_owner is an enterprise-owned organization (spending limit)" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 77, threshold: 75, tags: ["shared_storage"])
        ]
        highest_priority_notification = UsageNotification.new(@org_with_business, results: results).highest_priority_notification
        assert_equal "Your enterprise has used 90% of included services for GitHub Actions and Packages.", highest_priority_notification.text
      end

      test "returns Enterprise budget copy when owner is a Business" do
        GitHub.flipper[:ghe_spending_limits].enable(@business)
        results = [
          Result.new(value: 77, threshold: 75, tags: [:spending_limit]),
        ]

        highest_priority_notification = UsageNotification.new(@business, results: results).highest_priority_notification
        assert_match "Enterprise budget", highest_priority_notification.text
      end
    end

    context "#product_tags" do
      test "only provides products on the highest threshold" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 96, threshold: 90, tags: ["packages"]),
          Result.new(value: 77, threshold: 75, tags: ["shared_storage"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal %w[actions packages], highest_priority_notification.product_tags
      end

      test "filters product tags that aren't available" do
        results = [
          Result.new(value: 95, threshold: 90, tags: ["actions"]),
          Result.new(value: 95, threshold: 90, tags: ["packages"]),
          Result.new(value: 95, threshold: 90, tags: ["invalid_product"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal %w[actions packages], highest_priority_notification.product_tags
      end

      test "prefers spending limit products" do
        results = [
          Result.new(value: 77, threshold: 75, tags: ["packages", :spending_limit]),
          Result.new(value: 95, threshold: 90, tags: ["actions"])
        ]
        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal %w[packages spending_limit], highest_priority_notification.product_tags
      end
    end

    test "mail_subject prefers spending limit over entitlements" do
      results = [
        Result.new(value: 77, threshold: 75, tags: [:spending_limit]),
        Result.new(value: 95, threshold: 90, tags: ["actions"])
      ]
      highest_priority_notification = UsageNotification.new(@user, results: results, product: "actions").highest_priority_notification
      assert_equal "You've hit 75% of your spending limit", highest_priority_notification.mail_subject
    end

    test "mail_subject formats included entitlements thresholds" do
      results = [
        Result.new(value: 95, threshold: 90, tags: ["actions"]),
        Result.new(value: 96, threshold: 90, tags: ["packages"]),
        Result.new(value: 76, threshold: 75, tags: ["shared_storage"])
      ]
      highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
      assert_equal "You've used 90% of included services", highest_priority_notification.mail_subject
    end

    test "mail_product_title formats differently based on product" do
      spending_limit_results = [Result.new(value: 95, threshold: 90, tags: [:spending_limit])]
      highest_priority_notification = UsageNotification.new(@user, results: spending_limit_results).highest_priority_notification
      assert_equal "Spending limit usage", highest_priority_notification.mail_product_title

      # UsageNotification implementation currently mixes some spending-limit concepts with entitlements_usages
      # when product is nil - this should be fixed
      highest_priority_notification = UsageNotification.new(@user, results: @results).highest_priority_notification
      assert_equal "Spending limit usage", highest_priority_notification.mail_product_title

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "actions").highest_priority_notification
      assert_equal "GitHub Actions usage", highest_priority_notification.mail_product_title

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "packages").highest_priority_notification
      assert_equal "GitHub Packages usage", highest_priority_notification.mail_product_title

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "shared_storage").highest_priority_notification
      assert_equal "Shared storage usage", highest_priority_notification.mail_product_title
    end

    test "mail_icon formats differently based on product" do
      spending_limit_results = [Result.new(value: 95, threshold: 90, tags: [:spending_limit])]
      highest_priority_notification = UsageNotification.new(@user, results: spending_limit_results).highest_priority_notification
      assert_equal "cogs.png", highest_priority_notification.mail_icon

      # UsageNotification implementation currently mixes some spending-limit concepts with entitlements_usages
      # when product is nil - this should be fixed
      highest_priority_notification = UsageNotification.new(@user, results: @results).highest_priority_notification
      assert_equal "cogs.png", highest_priority_notification.mail_icon

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "actions").highest_priority_notification
      assert_equal "actions.png", highest_priority_notification.mail_icon

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "packages").highest_priority_notification
      assert_equal "packages.png", highest_priority_notification.mail_icon

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "shared_storage").highest_priority_notification
      assert_equal "hosting.png", highest_priority_notification.mail_icon
    end

    test "progress_bar_title formats spending limit if one is in the results" do
      results = [
        Result.new(value: 77, threshold: 75, tags: [:spending_limit]),
        Result.new(value: 95, threshold: 90, tags: ["actions"])
      ]
      highest_priority_notification = UsageNotification.new(@user, results: results, product: "actions").highest_priority_notification
      assert_equal "Spending limit", highest_priority_notification.progress_bar_title
    end

    test "progress_bar_title formats differently depending on the product" do
      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "actions").highest_priority_notification
      assert_equal "Private repository usage", highest_priority_notification.progress_bar_title

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "packages").highest_priority_notification
      assert_equal "Data transfer out", highest_priority_notification.progress_bar_title

      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "shared_storage").highest_priority_notification
      assert_equal "Storage used", highest_priority_notification.progress_bar_title
    end

    test "progress_bar_details_text formats spending limit based on the context" do
      results = [
        Result.new(value: 77, threshold: 75, tags: [:spending_limit],
        context: { used: 10.50, available: 13.75 }),
        Result.new(value: 95, threshold: 90, tags: ["actions"])
      ]
      highest_priority_notification = UsageNotification.new(@user, results: results, product: "actions").highest_priority_notification
      assert_equal "$10.5 of $13.75", highest_priority_notification.progress_bar_details_text
    end

    test "progress_bar_details_text formats based on the product context" do
      results = [
        Result.new(value: 95, threshold: 90, tags: ["actions"], context: { used: 950.0, available: 1000.0 })
      ]
      highest_priority_notification = UsageNotification.new(@user, results: results, product: "actions").highest_priority_notification
      assert_equal "950.0 of 1,000.0 mins included", highest_priority_notification.progress_bar_details_text

      highest_priority_notification = UsageNotification.new(@user, results: results, product: "packages").highest_priority_notification
      assert_equal "950.0GB of 1,000.0GB included", highest_priority_notification.progress_bar_details_text

      highest_priority_notification = UsageNotification.new(@user, results: results, product: "shared_storage").highest_priority_notification
      assert_equal "950.0MB of 1,000.0MB included", highest_priority_notification.progress_bar_details_text
    end

    test "usage_reset_date_text formats the first metered cycle" do
      @user.stubs(next_metered_billing_cycle_starts_at: Date.new(2020, 11, 05))
      highest_priority_notification = UsageNotification.new(@user, results: @results, product: "actions").highest_priority_notification
      assert_equal "Your usage will reset on November 05, 2020", highest_priority_notification.usage_reset_date_text
    end

    context "#disabled_services" do
      test "none disabled for warn-level entitlements usage notification" do
        results = [
          Result.new(value: 90, threshold: 90, tags: ["actions"], context: { used: 900.0, available: 900.0 }),
          Result.new(value: 90, threshold: 90, tags: ["packages"], context: { used: 900.0, available: 900.0 }),
          Result.new(value: 90, threshold: 90, tags: ["shared_storage"], context: { used: 900.0, available: 900.0 })
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_nil highest_priority_notification.disabled_services
      end

      test "none disabled for warn-level spending limits notification" do
        results = [
          Result.new(value: 90, threshold: 90, tags: ["actions", :spending_limit], context: { used: 900.0, available: 900.0 }),
          Result.new(value: 90, threshold: 90, tags: ["packages", :spending_limit], context: { used: 900.0, available: 900.0 }),
          Result.new(value: 90, threshold: 90, tags: ["shared_storage", :spending_limit], context: { used: 900.0, available: 900.0 })
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_nil highest_priority_notification.disabled_services
      end

      test "none disabled for error-level entitlements notification when spending limits available" do
        results = [
          Result.new(value: 100, threshold: 100, tags: ["actions"], context: { used: 1000.0, available: 1000.0 }),
          Result.new(value: 90, threshold: 90, tags: ["actions", :spending_limit], context: { used: 900.0, available: 900.0 }),
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_nil highest_priority_notification.disabled_services
      end

      test "displays actions and packages as disabled for error-level spending limits notification" do
        results = [
          Result.new(value: 100, threshold: 100, tags: ["actions", :spending_limit], context: { used: 1000.0, available: 1000.0 }),
          Result.new(value: 100, threshold: 100, tags: ["packages", :spending_limit], context: { used: 1000.0, available: 1000.0 }),
          Result.new(value: 100, threshold: 100, tags: ["shared_storage", :spending_limit], context: { used: 1000.0, available: 1000.0 })
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "GitHub Actions and Packages", highest_priority_notification.disabled_services
      end

      test "displays actions and packages as disabled for error-level entitlements notification" do
        results = [
          Result.new(value: 100, threshold: 100, tags: ["actions"], context: { used: 1000.0, available: 1000.0 }),
          Result.new(value: 100, threshold: 100, tags: ["packages"], context: { used: 1000.0, available: 1000.0 }),
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "GitHub Actions and Packages", highest_priority_notification.disabled_services

        results = [Result.new(value: 100, threshold: 100, tags: ["shared_storage"], context: { used: 1000.0, available: 1000.0 })]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "GitHub Actions and Packages", highest_priority_notification.disabled_services
      end

      test "displays actions as disabled for error-level entitlements notification with actions scope" do
        results = [
          Result.new(value: 100, threshold: 100, tags: ["actions"], context: { used: 1000.0, available: 1000.0 }),
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "GitHub Actions", highest_priority_notification.disabled_services
      end

      test "displays packages as disabled for error-level entitlements notification with packages scope" do
        results = [
          Result.new(value: 100, threshold: 100, tags: ["packages"], context: { used: 1000.0, available: 1000.0 }),
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "GitHub Packages", highest_priority_notification.disabled_services
      end
    end

    context "#usage_reset_date_text" do
      test "should format billing cycle as date" do
        results = [Result.new(value: 95, threshold: 90, tags: ["actions"])]

        Timecop.freeze do
          usage_reset_date_text = UsageNotification.new(@user, results: results).usage_reset_date_text
          assert_equal "Your usage will reset on #{@user.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}", usage_reset_date_text
        end
      end
    end

    context "#codespaces_action_test" do
      test "returns text for entitlements notification and owner does not allow overages - not paid, FF off" do
        GitHub.flipper[:codespaces_usage_notification_copy_update].disable
        results = [Result.new(value: 77, threshold: 75, tags: ["codespaces"])]

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "Navigate to <a href=\"https://github.com/codespaces\">github.com/codespaces</a> where you can see a list of your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. For more information see &quot;<a href=\"https://github.com/community/community/discussions/39697\">Making the most of your included free Codespaces usage</a>&quot;.", highest_priority_notification.action_text
      end

      test "returns text for entitlements notification and owner does not allow overages - not paid" do
        results = [Result.new(value: 77, threshold: 75, tags: ["codespaces"])]

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can <a href=\"https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch\">export your unpushed work to a branch.</a> To see a full list of your usage, obtain a copy of your <a href=\"https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage\">usage report</a> to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a <a href=\"https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace\">codespace</a> or <a href=\"https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration\">delete prebuilds for a repository.</a>", highest_priority_notification.action_text
      end

      test "returns text for spending limit notification - not paid, FF off" do
        GitHub.flipper[:codespaces_usage_notification_copy_update].disable

        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "Navigate to <a href=\"https://github.com/codespaces\">github.com/codespaces</a> where you can see a list of your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. For more information see &quot;<a href=\"https://github.com/community/community/discussions/39697\">Making the most of your included free Codespaces usage</a>&quot;.", highest_priority_notification.action_text
      end

      test "returns text for spending limit notification - not paid" do
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can <a href=\"https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch\">export your unpushed work to a branch.</a> To see a full list of your usage, obtain a copy of your <a href=\"https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage\">usage report</a> to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a <a href=\"https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace\">codespace</a> or <a href=\"https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration\">delete prebuilds for a repository.</a>", highest_priority_notification.action_text
      end

      test "returns text for entitlements notification and owner does not allow overages - paid, FF off" do
        GitHub.flipper[:codespaces_usage_notification_copy_update].disable
        @user.plan = GitHub::Plan.pro
        results = [Result.new(value: 77, threshold: 75, tags: ["codespaces"])]

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "Navigate to <a href=\"https://github.com/codespaces\">github.com/codespaces</a> where you can see a list of your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. For more information see &quot;<a href=\"https://github.com/community/community/discussions/39697\">Making the most of your included free Codespaces usage</a>&quot;.", highest_priority_notification.action_text
      end

      test "returns text for entitlements notification and owner does not allow overages - paid" do
        @user.plan = GitHub::Plan.pro
        results = [Result.new(value: 77, threshold: 75, tags: ["codespaces"])]

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can <a href=\"https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch\">export your unpushed work to a branch.</a> To see a full list of your usage, obtain a copy of your <a href=\"https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage\">usage report</a> to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a <a href=\"https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace\">codespace</a> or <a href=\"https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration\">delete prebuilds for a repository.</a>", highest_priority_notification.action_text
      end

      test "returns text for spending limit notification - paid, FF off" do
        GitHub.flipper[:codespaces_usage_notification_copy_update].disable
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]
        @user.plan = GitHub::Plan.pro

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "Navigate to <a href=\"https://github.com/codespaces\">github.com/codespaces</a> where you can see a list of your codespaces, export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. For more information see &quot;<a href=\"https://github.com/community/community/discussions/39697\">Making the most of your included free Codespaces usage</a>&quot;.", highest_priority_notification.action_text
      end

      test "returns text for spending limit notification - paid" do
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]
        @user.plan = GitHub::Plan.pro

        highest_priority_notification = UsageNotification.new(@user, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "When your allotment is exhausted, you won&#39;t be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month. If you want to access your in progress work from a codespace, you can <a href=\"https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch\">export your unpushed work to a branch.</a> To see a full list of your usage, obtain a copy of your <a href=\"https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage\">usage report</a> to see the codespaces and prebuilds created by your account. The usage report is the only place where prebuild usage is visible. If you see charges you&#39;d like to stop going forward, you can delete a <a href=\"https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace\">codespace</a> or <a href=\"https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration\">delete prebuilds for a repository.</a>", highest_priority_notification.action_text
      end

      test "uses budget as the generic configurable name for Enterprise Accounts" do
        GitHub.flipper[:ghe_spending_limits].enable(@business)
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]

        highest_priority_notification = UsageNotification.new(@business, results: results, product: CODESPACES_COMPUTE_PRODUCT).highest_priority_notification

        assert_equal "To continue using Codespaces uninterrupted, update your budget.", highest_priority_notification.action_text
      end
    end

    context "#action_text" do
      test "returns text for entitlements notification and owner does not allow overages" do
        results = [Result.new(value: 77, threshold: 75, tags: ["actions"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "To continue using Actions & Packages uninterrupted, update your spending limit.", highest_priority_notification.action_text
      end

      test "returns text for entitlements notification and owner has a spending limit" do
        results = [Result.new(value: 77, threshold: 75, tags: ["actions"])]
        create(:billing_budget, :enforce, owner: @user, spending_limit_in_subunits: 1_00)

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "You will be billed for usage beyond the included services and it will count towards your spending limit of $1.00.", highest_priority_notification.action_text
      end

      test "returns text for entitlements notification and owner has a spending limit set to unlimited" do
        results = [Result.new(value: 77, threshold: 75, tags: ["actions"])]
        Billing::BudgetLimit::FindBudget.expects(:for_account).with(@user, true).once.returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
        create(:billing_budget, :unlimited_spending, owner: @user)

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "You will be billed for usage beyond the included services. To avoid extra expenses, manage your spending limit.", highest_priority_notification.action_text
      end

      test "returns text for spending limit notification" do
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert_equal "To continue using Actions & Packages uninterrupted, update your spending limit.", highest_priority_notification.action_text
      end

      test "uses budget as the generic configurable name for Enterprise Accounts" do
        GitHub.flipper[:ghe_spending_limits].enable(@business)
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]

        highest_priority_notification = UsageNotification.new(@business, results: results).highest_priority_notification

        assert_equal "To continue using Actions & Packages uninterrupted, update your budget.", highest_priority_notification.action_text
      end
    end

    context "#show_progress_bar" do
      test "returns true for spending limit notifications" do
        results = [Result.new(value: 77, threshold: 75, tags: [:spending_limit])]
        create(:billing_budget, :enforce, owner: @user, spending_limit_in_subunits: 1_00)

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification

        assert highest_priority_notification.show_progress_bar
      end

      test "returns false for entitlement notifications when owner allows overages" do
        results = [Result.new(value: 77, threshold: 75, tags: ["actions"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert highest_priority_notification.show_progress_bar

        create(:billing_budget, :enforce, owner: @user, spending_limit_in_subunits: 1_00)

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        refute highest_priority_notification.show_progress_bar
      end
    end

    context "#slack_notification_message" do
      test "should prefer spending limit" do
        results = [
          Result.new(value: 77, threshold: 75, tags: [:spending_limit]),
          Result.new(value: 95, threshold: 90, tags: ["actions"])
        ]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "used 77% of paid usage services", highest_priority_notification.slack_notification_message
      end

      test "should prioritize spending limit" do
        results = [Result.new(value: 91, threshold: 90, tags: ["actions", :spending_limit])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        assert_equal "used 91% of paid usage services", highest_priority_notification.slack_notification_message
      end

      test "all products should be 100" do
        # products
        results = [Result.new(value: 100, threshold: 100, tags: ["actions"]),
                   Result.new(value: 100, threshold: 100, tags: ["packages"]),
                   Result.new(value: 100, threshold: 100, tags: ["shared_storage"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 100, actions: 100, packages: 100, storage: 100)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "all products should be over 90" do
        results = [Result.new(value: 91, threshold: 90, tags: ["actions"]),
                   Result.new(value: 92, threshold: 90, tags: ["packages"]),
                   Result.new(value: 93, threshold: 90, tags: ["shared_storage"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 90, actions: 91, packages: 92, storage: 93)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "all products should be over 75" do
        results = [Result.new(value: 76, threshold: 75, tags: ["actions"]),
                   Result.new(value: 77, threshold: 75, tags: ["packages"]),
                   Result.new(value: 78, threshold: 75, tags: ["shared_storage"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 75, actions: 76, packages: 77, storage: 78)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "all products should be 0" do
        results = [Result.new(value: 0, threshold: 0, tags: ["actions"]),
                   Result.new(value: 0, threshold: 0, tags: ["packages"]),
                   Result.new(value: 0, threshold: 0, tags: ["shared_storage"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 0, actions: 0, packages: 0, storage: 0)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "actions product should be over 75" do
        results = [Result.new(value: 76, threshold: 75, tags: ["actions"]),
                   Result.new(value: 0, threshold: 0, tags: ["packages"]),
                   Result.new(value: 0, threshold: 0, tags: ["shared_storage"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 75, actions: 76, packages: 0, storage: 0)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "packages product should be over 90" do
        results = [Result.new(value: 91, threshold: 90, tags: ["packages"]),
                   Result.new(value: 0, threshold: 0, tags: ["actions"]),
                   Result.new(value: 0, threshold: 0, tags: ["shared_storage"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 90, actions: 0, packages: 91, storage: 0)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "storage product should be 100" do
        results = [Result.new(value: 100, threshold: 100, tags: ["shared_storage"]),
                   Result.new(value: 0, threshold: 0, tags: ["actions"]),
                   Result.new(value: 0, threshold: 0, tags: ["packages"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 100, actions: 0, packages: 0, storage: 100)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "solo action result should be 100" do
        results = [Result.new(value: 100, threshold: 100, tags: ["actions"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 100, actions: 100, packages: 0, storage: 0)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end

      test "duo action result should be 100" do
        results = [Result.new(value: 100, threshold: 100, tags: ["actions"]),
                   Result.new(value: 100, threshold: 100, tags: ["packages"])]

        highest_priority_notification = UsageNotification.new(@user, results: results).highest_priority_notification
        expected = expected_slack_message(usage: 100, actions: 100, packages: 100, storage: 0)
        assert_equal expected, highest_priority_notification.slack_notification_message
      end
    end

    context "#shared_storage_consumed_mb_month" do
      test "return the correct estimated EoM value" do
        GitHub.flipper[:billing_large_event_windows].disable
        Timecop.freeze(@user.next_metered_billing_cycle_starts_at.change(month: 5, day: 27)) do
          mock_get_usage_breakdown(
            products: @product_breakdowns,
            entitlements: [@actions_entitlements, @shared_storage_entitlements, @packages_entitlements],
            budgets: []
          )
          current_storage_on_disk = 100.megabytes
          FactoryBot.create(:shared_storage_current_usage, :private_visibility, owner: @user, aggregate_size_in_bytes: current_storage_on_disk)
          usage_notification = UsageNotification.new(@user, evaluator: @evaluator)

          estimated_consumed_mb_months = 100 + (current_storage_on_disk * 5.days.in_hours / Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH / 1.megabyte).to_i

          assert_equal estimated_consumed_mb_months, usage_notification.shared_storage_consumed_mb_month
        end
      end

      test "returns the EoM value without estimation when flag is enabled" do
        GitHub.flipper[:billing_large_event_windows].enable
        Timecop.freeze(@user.next_metered_billing_cycle_starts_at.change(month: 5, day: 27)) do
          mock_get_usage_breakdown(
            products: @product_breakdowns,
            entitlements: [@actions_entitlements, @shared_storage_entitlements, @packages_entitlements],
            budgets: []
          )
          current_storage_on_disk = 100.megabytes
          FactoryBot.create(:shared_storage_current_usage, :private_visibility, owner: @user, aggregate_size_in_bytes: current_storage_on_disk)
          usage_notification = UsageNotification.new(@user, evaluator: @evaluator)

          assert_equal 100, usage_notification.shared_storage_consumed_mb_month
        end
      end
    end

    context "#shared_budget_total_spent" do
      test "#shared_budget_total_spent returns the total spending on Actions, Packages and Shared Storage" do
        budget_array = create_budget_array(id: @shared_budget.id, total_spent_in_subunits: 100)

        mock_get_usage_breakdown(
          products: @product_breakdowns,
          entitlements: [@actions_entitlements, @shared_storage_entitlements, @packages_entitlements],
          budgets: budget_array
        )
        usage_notification = UsageNotification.new(@business, evaluator: @evaluator)
        total_spent = usage_notification.shared_budget_total_spent

        assert_equal 1, total_spent
      end

      test "includes shared_storage estimated usage" do
        GitHub.flipper[:billing_large_event_windows].disable
        Timecop.freeze(@user.next_metered_billing_cycle_starts_at.change(month: 5, day: 27)) do
          mb_hours_consued_so_far = 512 * Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH

          mock_get_usage_breakdown(
            products: @product_breakdowns,
            entitlements: [@actions_entitlements, @shared_storage_entitlements.merge(consumed_quantity: mb_hours_consued_so_far), @packages_entitlements],
            budgets: []
          )
          current_storage_on_disk = 10.gigabytes
          FactoryBot.create(:shared_storage_current_usage, :private_visibility, owner: @user, aggregate_size_in_bytes: current_storage_on_disk)
          usage_notification = UsageNotification.new(@user, evaluator: @evaluator)

          estimated_shared_storage_overage = (current_storage_on_disk * 5.days.in_hours / 1.megabyte).to_i * 0.000000328

          assert_equal estimated_shared_storage_overage.round(2), usage_notification.shared_budget_total_spent
        end
      end

      test "does not include shared_storage estimated usage when flag is enabled" do
        GitHub.flipper[:billing_large_event_windows].enable
        Timecop.freeze(@user.next_metered_billing_cycle_starts_at.change(month: 5, day: 27)) do
          mb_hours_consued_so_far = 512 * Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH

          mock_get_usage_breakdown(
            products: @product_breakdowns,
            entitlements: [@actions_entitlements, @shared_storage_entitlements.merge(consumed_quantity: mb_hours_consued_so_far), @packages_entitlements],
            budgets: []
          )
          current_storage_on_disk = 10.gigabytes
          FactoryBot.create(:shared_storage_current_usage, :private_visibility, owner: @user, aggregate_size_in_bytes: current_storage_on_disk)
          usage_notification = UsageNotification.new(@user, evaluator: @evaluator)

          assert_equal 0, usage_notification.shared_budget_total_spent
        end
      end
    end

    context "#shared_budget_percentage_spent" do
      test "returns the percentage spent on Actions, Packages and Shared Storage" do
        budget_array = create_budget_array(id: @shared_budget.id, total_spent_in_subunits: 100)

        mock_get_usage_breakdown(
          products: @product_breakdowns,
          entitlements: [@actions_entitlements, @shared_storage_entitlements, @packages_entitlements],
          budgets: budget_array
        )
        usage_notification = UsageNotification.new(@business, evaluator: @evaluator)
        percentage = usage_notification.shared_budget_percentage_spent

        assert_equal percentage, 100
      end

      test "return 0 for unlimted budgets" do
        @shared_budget.update!(enforce_spending_limit: false)
        budget_array = create_budget_array(id: @shared_budget.id, total_spent_in_subunits: 100)

        mock_get_usage_breakdown(
          products: @product_breakdowns,
          entitlements: [@actions_entitlements, @shared_storage_entitlements, @packages_entitlements],
          budgets: budget_array
        )
        usage_notification = UsageNotification.new(@business, evaluator: @evaluator)
        percentage = usage_notification.shared_budget_percentage_spent

        assert_equal percentage, 0
      end
    end

    def expected_slack_message(usage:, actions:, packages:, storage:)
      if usage < 75
        <<~HEREDOC
          used less than 75% of included services
          Actions mins: #{actions}% used
          Packages bandwidth: #{packages}% used
          Shared storage for Actions/Packages: #{storage}% used
        HEREDOC
      else
        <<~HEREDOC
          used #{usage}% of included services
          Actions mins: #{actions}% used
          Packages bandwidth: #{packages}% used
          Shared storage for Actions/Packages: #{storage}% used
        HEREDOC
      end
    end
  end
end
