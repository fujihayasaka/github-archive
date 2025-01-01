# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module BillingAndLicensing
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def billing_menu_groups
        groups = []
        overview_items = [billing_overview_menu_item]
        overview_items << billing_usage_menu_item unless show_billing_premium_requests_usage_menu_item?
        groups << EnterpriseNavigation::Group.new(links: overview_items)

        groups << usage_folding_group if show_billing_premium_requests_usage_menu_item?

        if add_licensing_menu_item?
          groups << EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FLAT,
            links: [billing_license_menu_item]
          )
        end

        groups.concat([cost_group, payment_group, apps_group])
        groups
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def billing_menu_items
        billing_menu_groups.flat_map(&:links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def overview_group
        menu_items = []
        menu_items << billing_overview_menu_item
        menu_items << billing_usage_menu_item unless show_billing_premium_requests_usage_menu_item?
        menu_items << billing_license_menu_item if add_licensing_menu_item?
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def usage_folding_group
        menu_items = []
        menu_items << billing_metered_usage_menu_item
        menu_items << billing_premium_requests_usage_menu_item if show_billing_premium_requests_usage_menu_item?
        EnterpriseNavigation::Group.new(
          type: EnterpriseNavigation::GroupType::FOLDING,
          name: "Usage",
          icon: :graph,
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def cost_group
        menu_items = []
        menu_items << billing_cost_centers_menu_item
        menu_items << billing_budget_and_alerts_menu_item
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def payment_group
        menu_items = []
        menu_items << billing_payment_information_menu_item if add_payment_information_menu_item?
        menu_items << billing_payment_history_menu_item if add_payment_history_menu_item?
        menu_items << billing_past_invoices_menu_item if add_past_invoices_menu_item?
        menu_items << billing_contacts_menu_item if add_billing_contacts_menu_item?
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def apps_group
        menu_items = []
        menu_items << billing_marketplace_apps_menu_item if business&.billed_via_billing_platform? && business_budget_permission&.show_marketplace_apps_tab?
        menu_items << billing_sponsorships_menu_item if business&.billed_via_billing_platform? && business_budget_permission&.show_sponsorships_tab?
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_overview_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Overview",
          link_path: enterprise_billing_path(business),
          highlight: %i(
              business_billing_vnext_overview
            ),
          icon: :home
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_metered_usage_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Metered usage",
          link_path: enterprise_billing_usage_path(business),
          highlight: %i(
            business_billing_vnext_usage
          ),
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_usage_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Usage",
          link_path: enterprise_billing_usage_path(business),
          highlight: %i(
            business_billing_vnext_usage
          ),
          icon: :graph
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_cost_centers_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Cost centers",
          link_path: enterprise_billing_cost_centers_path(business),
          highlight: %i(
            business_billing_vnext_cost_centers
          ),
          icon: :organization
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_budget_and_alerts_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Budgets and alerts",
          link_path: enterprise_billing_budgets_path(business),
          highlight: %i(
            business_billing_vnext_budgets_alerts
          ),
          icon: :bell
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_license_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Licensing",
          link_path: enterprise_licensing_path(business),
          highlight: %i(
            business_licensing
          ),
          icon: :law
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_payment_information_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Payment information",
          link_path: enterprise_billing_payment_information_path(business),
          highlight: %i(
            business_billing_vnext_billing_payment_information
          ),
          icon: :"credit-card"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_payment_history_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Payment history",
          link_path: enterprise_billing_payment_history_index_path(business),
          highlight: %i(
            business_billing_vnext_payment_history
          ),
          icon: :log
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_past_invoices_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Past invoices",
          link_path: enterprise_billing_past_invoices_path(business),
          highlight: %i(
            business_billing_vnext_past_invoices
          ),
          icon: :file
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_contacts_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Billing contacts",
          link_path: enterprise_billing_contacts_path(business),
          highlight: %i(
            business_billing_vnext_billing_contacts
          ),
          icon: :people
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_marketplace_apps_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Marketplace apps",
          link_path: enterprise_billing_marketplace_apps_path(business),
          highlight: %i(
            business_billing_vnext_marketplace_apps
          ),
          icon: :apps
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_sponsorships_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Sponsorships",
          link_path: enterprise_billing_sponsorships_path(business),
          highlight: %i(
            business_billing_vnext_sponsorships
          ),
          icon: :heart
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_premium_requests_usage_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Premium request analytics",
          link_path: enterprise_billing_premium_requests_usage_index_path(business),
          highlight: %i(
            business_billing_vnext_premium_requests_usage
          ),
          label: premium_request_analytics_label,
        )
      end

      sig { returns(T::Boolean) }
      memoize def add_licensing_menu_item?
        return false unless business&.billed_via_billing_platform?
        return false unless business_owner? || business&.billing_manager?(user)

        true
      end

      sig { returns(T::Boolean) }
      memoize def add_payment_information_menu_item?
        add_licensing_menu_item?
      end

      sig { returns(T::Boolean) }
      memoize def add_payment_history_menu_item?
        return false unless business&.billed_via_billing_platform?
        return false unless business&.owner?(user) || business&.billing_manager?(user)
        return false unless business&.can_self_serve? && !business&.invoiced?

        true
      end

      sig { returns(T::Boolean) }
      memoize def add_billing_contacts_menu_item?
        add_licensing_menu_item?
      end

      sig { returns(T::Boolean) }
      memoize def add_past_invoices_menu_item?
        u = user
        return false unless business&.billed_via_billing_platform?
        return false if u.nil? # Ensure user is not nil

        business&.show_past_invoices_tab?(u) || false # Explicitly cast user to non-nil
      end

      sig { returns(T.nilable(Billing::Public::Budgets::Permission)) }
      memoize def business_budget_permission
        T.let(Billing::Public::Budgets::Permission.new(T.must(business), T.must(user)), T.nilable(::Billing::Public::Budgets::Permission))
      end

      private

      sig { returns(EnterpriseNavigation::Label) }
      def premium_request_analytics_label
        now = Time.now.utc
        september_29th_2025 = Time.utc(2025, 9, 29)
        december_1st_2025 = Time.utc(2025, 12, 1)

        if now < september_29th_2025
          EnterpriseNavigation::Label::PREVIEW
        elsif now < december_1st_2025
          EnterpriseNavigation::Label::NEW
        else
          EnterpriseNavigation::Label::PUBLIC
        end
      end
    end
  end
end
