# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class UsageNotification
      include UrlHelpers
      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::UrlHelper
      include GitHub::Memoizer

      delegate :billable_owner, to: :owner

      def initialize(owner, product: nil, budget_group: :shared, evaluator: nil, results: nil)
        @owner = owner
        @product = product
        @budget_group = budget_group
        @evaluator = evaluator.present? ? evaluator : default_threshold_evaluator
        @results = results || threshold_results
      end

      # Returns Billing::Notifications::UsageNotificationContent or nil
      def highest_priority_notification
        @highest_priority_notification ||= active_notifications.first
      end

      def active_notifications
        return [] if owner.billable_owner.plan.legacy?

        priority_ordered_notifications.map do |notification|
          serialize_notification(notification)
        end
      end

      def serialize_notification(notification)
        UsageNotificationContent.new(
          text: notification.text,
          threshold: notification.threshold,
          within_entitlements: notification.within_entitlements,
          scope: notification.scope,
          mail_icon: notification.mail_icon,
          mail_subject: notification.mail_subject,
          mail_product_title: notification.mail_product_title,
          show_progress_bar: show_progress_bar?(notification),
          progress_bar_title: notification.progress_bar_title,
          progress_bar_details_text: notification.progress_bar_details_text,
          usage_reset_date_text: usage_reset_date_text,
          slack_notification_message: notification.slack_notification_message,
          disabled_services: notification.disabled_services,
          filtered_by_tags: notification.filtered_by_tags,
          product_tags: notification.product_tags,
          meter_available: notification.meter_available,
          action_text: action_text(notification)
        )
      end

      def usage_reset_date_text
        "Your usage will reset on #{billable_owner.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
      end

      def metered_service_name
        if active_budget.product == "codespaces"
          "Codespaces"
        elsif active_budget.product == "shared"
          "Actions & Packages"
        else
          "metered services"
        end
      end

      # Text to be included with next actions
      #
      # Returns String
      def action_text(notification)
        if owner.delegate_billing_to_business? && notification.within_entitlements
          safe_join(["Your enterprise will be billed for usage beyond the included services. To avoid extra expenses, manage your enterprise's #{generic_budget_name} " \
          "or contact an ", link_to("enterprise owner", org_enterprise_owners_path(owner)), "."])
        elsif notification.within_entitlements && active_budget.unlimited_spending_limit?
          "You will be billed for usage beyond the included services. To avoid extra expenses, manage your #{generic_budget_name}."
        elsif notification.within_entitlements && active_budget.overage_allowed?
          spending_limit = Billing::Money.new(active_budget.spending_limit_in_subunits).format
          "You will be billed for usage beyond the included services and it will count towards your #{generic_budget_name} of #{spending_limit}."
        elsif owner.delegate_billing_to_business?
          safe_join(["To continue using #{metered_service_name} uninterrupted, update your enterprise's #{generic_budget_name} " \
            "or contact an ", link_to("enterprise owner", org_enterprise_owners_path(owner)), "."])
        elsif active_budget.product == "codespaces" && ::Codespaces::Policy.entitlements_feature_enabled?(owner)
          if GitHub.flipper[:codespaces_usage_notification_copy_update].enabled?(owner)
            export_url = "https://docs.github.com/codespaces/troubleshooting/exporting-changes-to-a-branch#exporting-changes-to-a-branch"
            usage_report_url = "https://docs.github.com/billing/managing-billing-for-github-codespaces/viewing-your-github-codespaces-usage"
            delete_codespace_url = "https://docs.github.com/codespaces/developing-in-codespaces/deleting-a-codespace#deleting-a-codespace"
            delete_prebuilds_url = "https://docs.github.com/codespaces/prebuilding-your-codespaces/managing-prebuilds#deleting-a-prebuild-configuration"
            messages = []
            messages << "When your allotment is exhausted, you won't be able to use Codespaces until you set up a spending limit or your free Codespaces allotment is reset next month."
            messages += [" If you want to access your in progress work from a codespace, you can ", link_to("export your unpushed work to a branch.", export_url)]
            messages += [
              " To see a full list of your usage, obtain a copy of your ", link_to("usage report", usage_report_url), " to see the codespaces and prebuilds created by your account. ",
              "The usage report is the only place where prebuild usage is visible. ",
              "If you see charges you'd like to stop going forward, you can delete a ", link_to("codespace", delete_codespace_url), " or ", link_to("delete prebuilds for a repository.", delete_prebuilds_url)
            ]

          else
            messages = ["Navigate to ", link_to("github.com/codespaces", codespaces_url(host: GitHub.url)),
              " where you can see a list of your codespaces, " \
              "export un-pushed work to a branch, delete old codespaces and prebuilds, or set up a spending limit to keep working in Codespaces beyond the included free usage. " \
              "For more information see \"",
              link_to("Making the most of your included free Codespaces usage", "https://github.com/community/community/discussions/39697"),
              "\"."]
          end

          if @product == Billing::Notifications::CODESPACES_STORAGE_PRODUCT && notification.threshold == 100
            messages << " Note that due to the exhaustion of storage included usage, new Codespaces Prebuilds are disabled until you set up a spending limit or your included usage quota is reset."
          end

          safe_join(messages)

        else
          # Spending limit notification or entitlements notification with no overages allowed.
          "To continue using #{metered_service_name} uninterrupted, update your #{generic_budget_name}."
        end
      end

      def generic_budget_name
        if owner.is_a?(Business) && GitHub.flipper[:ghe_spending_limits].enabled?(owner)
          "budget"
        else
          "spending limit"
        end
      end

      def show_progress_bar?(notification)
        if notification.within_entitlements && active_budget.overage_allowed?
          false
        else
          true
        end
      end

      def priority_ordered_notifications
        @priority_ordered_notifications ||= spending_limit_notifications + entitlement_notifications
      end

      def spending_limit_results
        @spending_limit_results ||= results.select do |result|
          any_spending_limit_tags?(result)
        end
      end

      def spending_limit_notifications
        @spending_limit_notifications ||= spending_limit_results.map do |result|
          SpendingLimitUsageNotification.new(owner, result: result, budget: active_budget)
        end
      end

      def entitlement_results
        @entitlement_results ||= results.reject do |result|
          any_spending_limit_tags?(result)
        end
      end

      def entitlement_results_by_threshold
        @entitlement_results_by_threshold ||= entitlement_results.group_by(&:threshold).sort.reverse
      end

      def entitlement_notifications
        @entitlement_notifications ||= entitlement_results_by_threshold.map do |_, threshold_results|
          EntitlementsUsageNotification.new(owner, product: product, results: threshold_results)
        end
      end

      def any_spending_limit_tags?(result)
        result.tags.map(&:to_s).any? do |t|
          Billing::Notifications::SHARED_SPENDING_LIMIT == t ||
            Billing::Notifications::CODESPACES_SPENDING_LIMIT == t
        end
      end

      def threshold_results
        threshold_results = if product
          evaluator.results(tags: [product, :spending_limit, :codespaces_spending_limit])
        else
          evaluator.results
        end
      end

      def active_budget
        return billable_owner_budget unless GitHub.flipper[:ghe_spending_limits].enabled?(billable_owner)
        owner_budget.persisted? ? owner_budget : billable_owner_budget
      end

      def owner_budget
        @owner_budget ||= if product
          owner.budget_for(product: product)
        else
          owner.budget_for(group: budget_group)
        end
      end

      def billable_owner_budget
        @billable_owner_budget ||= if product
          billable_owner.budget_for(product: product)
        else
          billable_owner.budget_for(group: budget_group)
        end
      end

      memoize def shared_storage_usage
        Billing::SharedStorageUsage.new(billable_owner)
      end

      memoize def shared_storage_entitlements
        usage_checker.entitlements_for(name: Billing::Notifications::SHARED_STORAGE_PRODUCT.titlecase)
      end

      memoize def shared_storage_consumed_mb_month
        amount_used = shared_storage_entitlements.consumed_quantity
        estimated_remaining_private_megabyte_hours_used = 0
        if !GitHub.flipper[:billing_large_event_windows].enabled?
          estimated_remaining_private_megabyte_hours_used = shared_storage_usage.additional_mb_hours_by_end_of_cycle
        end
        ((amount_used + estimated_remaining_private_megabyte_hours_used) / Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH).to_i
      end

      memoize def shared_storage_entitlements_allocated_mb_month
        allocated_mb_hours = shared_storage_entitlements.allocated_quantity
        allocated_mb_hours / Billing::SharedStorageUsage::HOURS_IN_ASSUMED_MONTH
      end

      def shared_storage_entitlements_used_percentage
        return 0 if shared_storage_entitlements_allocated_mb_month.zero?
        percent = shared_storage_consumed_mb_month / shared_storage_entitlements_allocated_mb_month
        [(percent * 100).to_i, 100].min
      end

      memoize def usage_checker
        product_names = if @product.present?
          [@product]
        else
          [
            Billing::Notifications::ACTIONS_PRODUCT,
            Billing::Notifications::GPR_PRODUCT,
            Billing::Notifications::SHARED_STORAGE_PRODUCT,
          ]
        end

        Billing::UsageChecker.new(
          account: owner,
          product_names: product_names,
          timeout: 5
        )
      end

      def shared_budget_total_spent
        usage_charged = usage_checker.total_spent_towards_budget(active_budget)
        usage_record = usage_checker.usage_for(product: Billing::Notifications::SHARED_STORAGE_PRODUCT, sku: "default", account_specific_lookup: false)
        estimated_additional_storage_cost = 0
        if !GitHub.flipper[:billing_large_event_windows].enabled?
          estimated_additional_storage_cost = if usage_record
            usage_record.additional_cost_in_subunits(additional_quantity: shared_storage_usage.additional_mb_hours_by_end_of_cycle)
          else
            0
          end
        end
        (usage_charged + estimated_additional_storage_cost) / 100.0
      end

      def shared_budget_percentage_spent
        return 0 if shared_budget_total_spent.zero?

        percent = (shared_budget_total_spent / Float(active_budget.usage_limit / 100.0)).round(2)

        # If the usage limit is 0, but total usage is a non-zero we will get Infinity
        # This could happen if user changes their limit, or when trade controls restricted
        return 100 if percent == Float::INFINITY
        [(percent * 100).to_i, 100].min
      end

      def default_threshold_evaluator
        evaluator = Evaluator.new(thresholds: THRESHOLDS.keys)
        notification_permission = Billing::Notifications::NotificationPermission.new(billable_owner, product: product)

        should_notify_for_paid_usage = ActiveRecord::Base.connected_to(role: :reading) { notification_permission.receive_notification_for_paid_usage? }
        should_notify_for_free_usage = ActiveRecord::Base.connected_to(role: :reading) { notification_permission.receive_notification_for_free_usage? }

        if active_budget.product == Billing::Notifications::CODESPACES_PRODUCT

          if ::Codespaces::Policy.entitlements_feature_enabled?(billable_owner)

            codespaces_usage = Billing::CodespacesUsage.new(account: billable_owner)
            # Adds codespace compute free/entitlements threshold
            evaluator.add_case(CODESPACES_COMPUTE_PRODUCT) do |context|
              next if should_notify_for_paid_usage && !should_notify_for_free_usage

              codespaces_compute_entitlement = codespaces_usage.compute_entitlement
              next unless codespaces_compute_entitlement.present?

              context[:used] = number_with_precision(codespaces_compute_entitlement.consumed_quantity, precision: 2)
              context[:available] = number_with_precision(codespaces_compute_entitlement.allocated_quantity, precision: 2)

              codespaces_compute_entitlement.consumed_percentage
            end

            # Adds codespace storage free/entitlements threshold
            evaluator.add_case(CODESPACES_STORAGE_PRODUCT) do |context|
              next if should_notify_for_paid_usage && !should_notify_for_free_usage

              codespaces_storage_entitlement = codespaces_usage.storage_entitlement
              next unless codespaces_storage_entitlement.present?

              context[:used] = number_with_precision(codespaces_storage_entitlement.consumed_quantity, precision: 2)
              context[:available] = number_with_precision(codespaces_storage_entitlement.allocated_quantity, precision: 2)

              codespaces_storage_entitlement.consumed_percentage
            end
          end

          evaluator.add_case(:codespaces_spending_limit) do |context|
            ActiveRecord::Base.connected_to(role: :reading) do
              next unless should_notify_for_paid_usage

              codespace_owner = GitHub.flipper[:ghe_spending_limits].enabled?(billable_owner) ? owner : billable_owner
              codespaces_spending_usage = Billing::CodespacesUsage.new(account: codespace_owner)

              context[:used] = codespaces_spending_usage.total_paid_usage_cost / 100.0
              context[:available] = codespaces_spending_usage.budget_limit / 100.0

              codespaces_spending_usage.spending_limit_percentage
            end
          end
        else
          # add actions free/entitlement threshold
          evaluator.add_case(ACTIONS_PRODUCT) do |context|
            ActiveRecord::Base.connected_to(role: :reading) do
              next if should_notify_for_paid_usage && !should_notify_for_free_usage

              actions_entitlements = usage_checker.entitlements_for(name: Billing::Notifications::ACTIONS_PRODUCT.titlecase)

              next if usage_checker.request_error? || actions_entitlements.nil?

              context[:used] = number_with_precision(actions_entitlements.consumed_quantity.to_i, precision: 2)
              context[:available] = number_with_precision(actions_entitlements.allocated_quantity, precision: 2)

              actions_entitlements.consumed_percentage
            end
          end

          # add packages free/entitlement threshold
          evaluator.add_case(GPR_PRODUCT) do |context|
            ActiveRecord::Base.connected_to(role: :reading) do
              next if should_notify_for_paid_usage && !should_notify_for_free_usage

              packages_registry_entitlements = usage_checker.entitlements_for(name: Billing::Notifications::GPR_PRODUCT.titlecase)

              next if usage_checker.request_error? || packages_registry_entitlements.nil?

              context[:used] = number_with_precision(packages_registry_entitlements.consumed_quantity, precision: 2)
              context[:available] = number_with_precision(packages_registry_entitlements.allocated_quantity, precision: 2)

              packages_registry_entitlements.consumed_percentage
            end
          end

          # add storage free/entitlement threshold
          evaluator.add_case(SHARED_STORAGE_PRODUCT) do |context|
            ActiveRecord::Base.connected_to(role: :reading) do
              next if should_notify_for_paid_usage && !should_notify_for_free_usage

              shared_storage_entitlements = usage_checker.entitlements_for(name: Billing::Notifications::SHARED_STORAGE_PRODUCT.titlecase)

              next if usage_checker.request_error? || shared_storage_entitlements.nil?

              context[:used] = shared_storage_consumed_mb_month
              context[:available] = shared_storage_entitlements_allocated_mb_month

              shared_storage_entitlements_used_percentage
            end
          end

          # paid threshold for shared budget
          evaluator.add_case(:spending_limit) do |context|
            ActiveRecord::Base.connected_to(role: :reading) do
              next unless should_notify_for_paid_usage
              next if usage_checker.request_error?

              context[:used] = shared_budget_total_spent
              context[:available] = active_budget.spending_limit_in_subunits / 100.0

              shared_budget_percentage_spent
            end
          end
        end

        evaluator
      end

      class SpendingLimitUsageNotification
        include ActionView::Helpers::NumberHelper

        def initialize(owner, result:, budget:)
          @owner = owner
          @result = result
          @budget = budget
        end

        def disabled_services
          if threshold >= Billing::Notifications::ERROR_THRESHOLD
            # TODO: This is not necessarily true. Actions/Packages are only disabled past entitlements usage.
            # This property is currently unused by any view (still coming from ::UsageNotifications).
            "GitHub Actions and Packages"
          else
            nil
          end
        end

        def metered_service_name
          if budget.product == "codespaces"
            "Codespaces"
          elsif budget.product == "shared"
            "Actions & Packages"
          else
            "metered services"
          end
        end

        def text
          if owner.is_a?(Business) && GitHub.flipper[:ghe_spending_limits].enabled?(owner)
            "You've used #{result.threshold}% of your Enterprise budget."
          elsif budget.enterprise_budget_for_org? && GitHub.flipper[:ghe_spending_limits].enabled?(owner.billable_owner)
            "You've used #{result.threshold}% of your organization spending limit for #{metered_service_name}."
          elsif owner.is_organization_billed_through_business?
            "Your enterprise has used #{result.threshold}% of its spending limit for #{metered_service_name}."
          else
            "You've used #{result.threshold}% of your spending limit for #{metered_service_name}."
          end
        end

        def threshold
          result.threshold
        end

        def within_entitlements
          false
        end

        def scope
          "spending-limit"
        end

        def mail_subject
          "You've hit #{result.threshold}% of your #{generic_budget_name}"
        end

        def mail_icon
          "cogs.png"
        end

        def mail_product_title
          "#{generic_budget_name.capitalize} usage"
        end

        def progress_bar_title
          generic_budget_name.capitalize
        end

        def progress_bar_details_text
          context = result.context
          return if context.blank?

          used = number_to_currency(context[:used], strip_insignificant_zeros: true)
          available = number_to_currency(context[:available], strip_insignificant_zeros: true)

          "#{used} of #{available}"
        end

        def slack_notification_message
          "used #{result.value}% of paid usage services"
        end

        def filtered_by_tags
          result.tags
        end

        def product_tags
          @product_tags ||= result.tags.flatten.map(&:to_s)
            .intersection(Billing::Notifications::AVAILABLE_PRODUCTS)
        end

        def meter_available
          context = result.context
          return unless context.present?

          result.context[:available]
        end

        private

        def generic_budget_name
          if owner.is_a?(Business) && GitHub.flipper[:ghe_spending_limits].enabled?(owner)
            "budget"
          else
            "spending limit"
          end
        end

        attr_reader :result, :owner, :budget
      end

      class EntitlementsUsageNotification
        include ActionView::Helpers::NumberHelper

        def initialize(owner, product: nil, results:)
          @owner = owner
          @product = product
          @results = results
        end

        def disabled_services
          actions_disabled = actions_result && actions_result.threshold >= Billing::Notifications::ERROR_THRESHOLD
          packages_disabled = packages_result && packages_result.threshold >= Billing::Notifications::ERROR_THRESHOLD
          storage_disabled = storage_result && storage_result.threshold >= Billing::Notifications::ERROR_THRESHOLD

          if storage_disabled || actions_disabled && packages_disabled
            "GitHub Actions and Packages"
          elsif actions_disabled
            "GitHub Actions"
          elsif packages_disabled
            "GitHub Packages"
          else
            nil
          end
        end

        def text
          base = if owner.is_organization_billed_through_business?
            "Your enterprise has used"
          else
            "You've used"
          end

          base + " #{results.first.threshold}% of included services for GitHub #{humanize_services_from_results(results).to_sentence}."
        end

        def threshold
          results.first.threshold
        end

        def within_entitlements
          true
        end

        def scope
          product
        end

        def mail_subject
          "You've used #{results.first.threshold}% of included services"
        end

        # UsageNotification implementation currently mixes some spending-limit concepts with entitlements_usages
        # when product is nil - this should be fixed
        def mail_icon
          case @product
          when Billing::Notifications::ACTIONS_PRODUCT then "actions.png"
          when Billing::Notifications::GPR_PRODUCT then "packages.png"
          when Billing::Notifications::SHARED_STORAGE_PRODUCT then "hosting.png"
          else
            "cogs.png"
          end
        end

        # UsageNotification implementation currently mixes some spending-limit concepts with entitlements_usages
        # when product is nil - this should be fixed
        def mail_product_title
          prefix =
            case @product
            when Billing::Notifications::ACTIONS_PRODUCT then "GitHub Actions"
            when Billing::Notifications::GPR_PRODUCT then "GitHub Packages"
            when Billing::Notifications::SHARED_STORAGE_PRODUCT then "Shared storage"
            when Billing::Notifications::CODESPACES_COMPUTE_PRODUCT then "GitHub Codespaces compute"
            when Billing::Notifications::CODESPACES_STORAGE_PRODUCT then "GitHub Codespaces storage"
            else
              "Spending limit"
            end
          "#{prefix} usage"
        end

        def progress_bar_title
          case product
          when Billing::Notifications::ACTIONS_PRODUCT then "Private repository usage"
          when Billing::Notifications::GPR_PRODUCT then "Data transfer out"
          when Billing::Notifications::SHARED_STORAGE_PRODUCT then "Storage used"
          when Billing::Notifications::CODESPACES_COMPUTE_PRODUCT then "Codespaces compute usage"
          when Billing::Notifications::CODESPACES_STORAGE_PRODUCT then "Codespaces storage usage"
          end
        end

        def progress_bar_details_text
          context = results.first.context
          return if context.blank?
          case product
          when Billing::Notifications::ACTIONS_PRODUCT
            "#{number_with_delimiter(context[:used])} of #{number_with_delimiter(context[:available])} mins included"
          when Billing::Notifications::GPR_PRODUCT
            "#{number_with_delimiter(context[:used])}GB of #{number_with_delimiter(context[:available])}GB included"
          when Billing::Notifications::SHARED_STORAGE_PRODUCT
            "#{number_with_delimiter(context[:used])}MB of #{number_with_delimiter(context[:available])}MB included"
          when Billing::Notifications::CODESPACES_COMPUTE_PRODUCT
            "#{number_with_delimiter(context[:used])} of #{number_with_delimiter(context[:available])} core hours included"
          when Billing::Notifications::CODESPACES_STORAGE_PRODUCT
            "#{number_with_delimiter(context[:used])}GB of #{number_with_delimiter(context[:available])}GB included"
          end
        end

        def slack_notification_message
          base =
            if threshold == Billing::Notifications::ERROR_THRESHOLD
              "used 100% of included services"
            elsif threshold == Billing::Notifications::WARN_THRESHOLD
              "used 90% of included services"
            elsif threshold == Billing::Notifications::INFO_THRESHOLD
              "used 75% of included services"
            else
              "used less than 75% of included services"
            end

          free_minutes_usage_percentage = actions_result&.value || 0
          free_data_usage_percentage = packages_result&.value || 0
          free_storage_usage_percentage = storage_result&.value || 0

          <<~MESSAGE
          #{base}
          #{Billing::Notifications::ACTIONS_PRODUCT.capitalize} mins: #{free_minutes_usage_percentage}% used
          #{Billing::Notifications::GPR_PRODUCT.capitalize} bandwidth: #{free_data_usage_percentage}% used
          #{Billing::Notifications::SHARED_STORAGE_PRODUCT.humanize.capitalize} for Actions/Packages: #{free_storage_usage_percentage}% used
          MESSAGE
        end

        def filtered_by_tags
          results.first.tags
        end

        def product_tags
          @product_tags ||= results.map(&:tags).flatten.map(&:to_s)
            .intersection(Billing::Notifications::AVAILABLE_PRODUCTS)
        end

        def meter_available
          context = results.first.context
          return unless context.present?

          results.first.context[:available]
        end

        private

        attr_reader :results, :owner, :product

        def humanize_services_from_results(results)
          results.map do |result|
            if result.tags.include?(Billing::Notifications::ACTIONS_PRODUCT)
              "Actions"
            elsif result.tags.include?(Billing::Notifications::GPR_PRODUCT)
              "Packages"
            elsif result.tags.include?(Billing::Notifications::SHARED_STORAGE_PRODUCT)
              "Storage (GitHub Actions and Packages)"
            elsif result.tags.include?(Billing::Notifications::CODESPACES_STORAGE_PRODUCT)
              "Codespaces storage"
            elsif result.tags.include?(Billing::Notifications::CODESPACES_COMPUTE_PRODUCT)
              "Codespaces compute"
            end
          end.compact.sort
        end

        def actions_result
          @actions_result ||= results.find { |r| r.tags.include?(Billing::Notifications::ACTIONS_PRODUCT) }
        end

        def packages_result
          @packages_result ||= results.find { |r| r.tags.include?(Billing::Notifications::GPR_PRODUCT) }
        end

        def storage_result
          @storage_result ||= results.find { |r| r.tags.include?(Billing::Notifications::SHARED_STORAGE_PRODUCT) }
        end
      end

      private

      attr_reader :results, :owner, :product, :budget_group, :evaluator
    end
  end
end
