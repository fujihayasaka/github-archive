# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class OnboardBillingPlatformCustomersController < StafftoolsController
      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
        "Stafftools::Billing::OnboardBillingPlatformCustomersController#create",
        "Stafftools::Billing::OnboardBillingPlatformCustomersController#destroy",
      ]

      before_action :dotcom_required
      before_action :validate_customer_ids, only: [:create]
      before_action :stafftools_onboarding_staff_required!

      depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Ballast,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      only: [:index, :create, :destroy, :new]

      depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :new], optional: true

      PER_PAGE = 30
      UNSUPPORTED_OFFBOARD_PRODUCTS = ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum.serialized_enums - [
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize
      ]

      PRODUCTS = [
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages,
      ].freeze

      def index
        bp_customers_by_id = if onboarded_customers.any?
          response = billing_platform_client.get_customers(
            customer_ids: onboarded_customers.pluck(:id).map(&:to_s)
          )
          if !response.is_a?(::Billing::Platform::Api::Error)
            response[:customers].index_by { |c| c[:customerId].to_i }
          else
            {}
          end
        end

        render("stafftools/billing/onboard_billing_platform_customers/index", locals: {
          customers: onboarded_customers,
          bp_customers: bp_customers_by_id,
          products: PRODUCTS,
        })
      end

      def new
        total_cohorts = ::Billing::BillingPlatformOnboardingCohort.total_cohorts
        all_cohorts = 1.upto(total_cohorts).map do |cohort_id|
          cohort_info = ::Billing::BillingPlatformOnboardingCohort.onboard_customers_cohort(cohort_id)
          {
            id: cohort_id,
            name: "Cohort #{cohort_id}",
            members_count: cohort_info[:total_customers],
            onboarded_count: cohort_info[:onboarded_customers],
            customer_ids: cohort_info[:customer_ids]
          }
        end

        render("stafftools/billing/onboard_billing_platform_customers/new", locals: {
          products: PRODUCTS,
          align: "left",
          number_of_panels: 2,
          cohorts: all_cohorts
        })
      end

      def create
        products = []
        if params[:new_product].nil?
          flash[:error] = "Please select a product"
          return redirect_to(action: :new)
        else
          products = params[:new_product].map do |product_id|
            ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum.from_serialized(product_id)
          end
        end
        Customer.where(id: customer_ids_arr).each do |customer|
          # TODO: Should we enqueue with some kind of rate limit to avoid a thundering heard?
          customer.onboard_to_billing_platform(products: products.map(&:serialize))
        end

        flash[:notice] = "You have successfully enqueued the customers for billing platform onboarding"
        redirect_to(action: :index)
      end

      def destroy
        product = params[:product]

        if UNSUPPORTED_OFFBOARD_PRODUCTS.include?(product)
          flash[:error] = "You cannot offboard a customer from #{product} in billing platform"
        else
          customer = Customer.find(params[:customer_id])
          ::Billing::OffboardCustomerFromProductInBillingPlatformJob.perform_later(customer_id: T.must(customer.id), product: product)
          flash[:notice] = "You're offboarding #{customer.name} from #{product} in billing platform"
        end
        redirect_to(action: :index)
      end

      private

      memoize def customer_ids
        params[:new_customer_ids]
      end

      memoize def number_to_onboard
        params.fetch(:number_to_onboard, 1).to_i
      end

      memoize def remaining_count
        params.fetch(:remaining_count, 1).to_i
      end

      memoize def customer_ids_arr
        initial_customer_ids = customer_ids.split(",").map(&:to_i)

        if number_to_onboard >= remaining_count
          flash[:notice] = "Number to onboard is greater than remaining count, will automatically onboard entire cohort"

          initial_customer_ids
        else
          customers = Customer.where(id: initial_customer_ids)
          not_billed_via_platform_customers = customers.reject { |customer| customer.billed_via_billing_platform? }
          selected_customers = not_billed_via_platform_customers.first(number_to_onboard)
          selected_ids = selected_customers.map(&:id)
        end
      end

      memoize def customer_duplicated_ids
        customer_ids_arr.select { |id| customer_ids_arr.count(id) > 1 }
      end

      def validate_customer_ids
        if customer_ids.blank?
          flash[:error] = "Couldn't find any customer ids"
          return redirect_to(action: :new)
        end
        unless customer_ids.match?(/^\s*\d+(?:\s*,\s*\d+)*\s*$/)
          flash[:error] = "Your list of customer ids is not valid, please use a comma separated list of customer ids"
          return redirect_to(action: :new)
        end

        bulk_id = params.fetch(:bulk_id, nil)
        if bulk_id.nil?
          flash[:notice] = "No cohort selected, validating customer ids for less than 100"
          if customer_ids_arr.length > 100
            flash[:error] = "Your list is larger than 100 customer ids, please keep it 100 and under"
            return redirect_to(action: :new)
          end
        end

        if customer_duplicated_ids.length > 0
          flash[:error] = "Please only add unique customer ids, you have inputted #{customer_duplicated_ids.uniq.join(", ")} more than once, please remove these customers and try again"
          redirect_to(action: :new)
        end
      end

      def stafftools_onboarding_staff_required!
        render_404 unless current_user.site_admin?
      end

      def billing_platform_client
        ::Billing::Platform::Api::Client.new
      end

      def onboarded_customers
        customer_id = params[:customer_id]
        product = params[:product]&.downcase

        customers = Customer.where(billed_via_billing_platform: true).includes(:billing_platform_enabled_product).order(:id)
        customers = customers.where(id: customer_id) if customer_id.present?
        customers = customers.where(billing_platform_enabled_product: { product => true }) if product.present?
        customers.paginate(page: current_page, per_page: PER_PAGE)
      end
    end
  end
end
