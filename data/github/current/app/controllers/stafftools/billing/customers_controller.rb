# typed: strict
# frozen_string_literal: true

require "set"

module Stafftools
  module Billing
    class CustomersController < StafftoolsController
      include GitHub::Memoizer
      include Stafftools::BillingHelper

      before_action :dotcom_required
      before_action :stafftools_billing_staff_required!
      before_action :set_customer, only: [:show]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Billing,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        only: [:index, :show]

      PER_PAGE = 30
      RECENT_CUSTOMERS_LIMIT = 10
      STATS_WINDOW_DAYS = 30

      sig { void }
      def index
        customers = if params[:query].present?
          find_customers(params[:query].strip)
        else
          Customer.none
        end

        recent_customers = unless params[:query].present?
          Customer
            .includes(:customer_accounts, :payment_method, :business, :plan_subscriptions)
            .order(created_at: :desc)
            .limit(RECENT_CUSTOMERS_LIMIT)
        end

        stats_since = STATS_WINDOW_DAYS.days.ago

        # Single query + in-memory rollup instead of three separate COUNT queries
        # to avoid MySQL statement timeouts on the customers table.
        recent_customer_stats = unless params[:query].present?
          Customer.where("created_at >= ?", stats_since).pluck(:billing_type, :locked_at)
        end
        recent_customer_stats ||= []

        render("stafftools/billing/customers/index", locals: {
          customers: customers,
          recent_customers: recent_customers || Customer.none,
          recent_card_count: recent_customer_stats.count { |billing_type, _| billing_type == "card" },
          recent_invoice_count: recent_customer_stats.count { |billing_type, _| billing_type == "invoice" },
          recent_locked_count: recent_customer_stats.count { |_, locked_at| locked_at.present? },
        })
      end

      sig { void }
      def show
        customer = T.must(@customer)
        payment_method = customer.payment_method
        plan_subscriptions = customer.plan_subscriptions.includes(:subscription_items)
        customer_accounts = customer.customer_accounts.includes(:user)
        show_billing_contact = can_view_billing_contact?

        render("stafftools/billing/customers/show", locals: {
          customer: customer,
          billable_owner: customer.billable_owner,
          payment_method: payment_method,
          plan_subscriptions: plan_subscriptions,
          customer_accounts: customer_accounts,
          show_billing_contact: show_billing_contact,
          billing_contact: show_billing_contact ? customer.billing_contact : nil,
        })
      end

      private

      sig { params(query: String).returns(T.untyped) }
      def find_customers(query)
        customer_ids = T.let(Set.new, T::Set[T.untyped])

        # Try numeric customer ID first
        if query.match?(/\A\d+\z/)
          customer_ids.merge(Customer.where(id: query.to_i).pluck(:id))
          return load_customers(customer_ids) if customer_ids.any?
        end

        # Exact match: user/org login via customer_accounts
        user = ::User.find_by(login: query)
        if user
          customer_ids.merge(CustomerAccount.where(user_id: user.id).pluck(:customer_id))

          # If org delegates billing to a business, include the business's customer
          if user.organization? && user.delegate_billing_to_business?
            delegated_business = user.billing_business
            customer_ids << delegated_business.customer.id if delegated_business&.customer
          end
        end

        # Exact match: business slug or name
        business = Business.find_by(slug: query) || Business.find_by(name: query)
        customer_ids << T.must(business.customer).id if business&.customer

        return load_customers(customer_ids) if customer_ids.any?

        # Fuzzy fallback: search users via Elasticsearch
        fuzzy_user_ids = fuzzy_user_search(query)
        if fuzzy_user_ids.any?
          customer_ids.merge(
            CustomerAccount.where(user_id: fuzzy_user_ids).pluck(:customer_id)
          )

          # Check if any fuzzy-matched users are orgs with delegated billing
          ::User.where(id: fuzzy_user_ids, type: "Organization").find_each do |org|
            if org.delegate_billing_to_business?
              delegated_business = org.billing_business
              customer_ids << delegated_business.customer.id if delegated_business&.customer
            end
          end
        end

        # Fuzzy fallback: search businesses via Elasticsearch
        fuzzy_business_ids = fuzzy_business_search(query)
        if fuzzy_business_ids.any?
          customer_ids.merge(
            Customer.joins(:business).where(businesses: { id: fuzzy_business_ids }).pluck(:id)
          )
        end

        load_customers(customer_ids)
      end

      sig { params(ids: T::Set[T.untyped]).returns(T.untyped) }
      def load_customers(ids)
        return Customer.none if ids.empty?

        Customer
          .where(id: ids.to_a)
          .includes(:customer_accounts, :payment_method, :business, :plan_subscriptions)
          .order(created_at: :desc)
          .limit(PER_PAGE)
      end

      sig { params(query: String).returns(T::Array[Integer]) }
      def fuzzy_user_search(query)
        finder = ::Search::Queries::UserFuzzyFinder.new(
          current_user: current_user,
          query: query,
          highlight: false,
        )
        results = finder.execute
        results.results.filter_map { |hit| hit["_model"]&.id }
      rescue => e
        Rails.logger.warn("Billing customers fuzzy user search failed: #{e.message}")
        []
      end

      sig { params(query: String).returns(T::Array[Integer]) }
      def fuzzy_business_search(query)
        return [] if GitHub.single_business_environment?

        es_query = ::Search::Queries::EnterpriseQuery.new(query: query)
        results = es_query.execute
        results.map { |hit| hit["_id"].to_i }
      rescue => e
        Rails.logger.warn("Billing customers fuzzy business search failed: #{e.message}")
        []
      end

      sig { void }
      def set_customer
        @customer = T.let(@customer, T.nilable(Customer))
        @customer = Customer
          .includes(:customer_accounts, :payment_method, :business, :plan_subscriptions, :organizations, :users)
          .find_by(id: params[:id])
        render_404 unless @customer
      end

      sig { void }
      def stafftools_billing_staff_required!
        render_404 unless current_user&.site_admin?
      end

      sig { returns(T::Boolean) }
      def can_view_billing_contact?
        Stafftools::AccessControl.authorized?(
          current_user,
          { controller: "Stafftools::Billing::Customers::BillingContactsController", action: "show" },
        )
      rescue
        false
      end
    end
  end
end
