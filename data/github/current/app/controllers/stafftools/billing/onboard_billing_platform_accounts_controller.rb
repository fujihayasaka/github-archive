# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class OnboardBillingPlatformAccountsController < StafftoolsController
      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
        "Stafftools::Billing::OnboardBillingPlatformAccountsController#create",
      ]

      before_action :dotcom_required
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
      only: [:create]

      PRODUCTS = [
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages,
      ].freeze

      PER_PAGE = 30
      MAX_SIZE = 100

      def index
        bp_customers_by_id = if onboarded_customers.exists?
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

      def create
        if user_ids_arr.length > MAX_SIZE
          flash[:error] = "You can only onboard up to #{MAX_SIZE} accounts at a time"
          return redirect_to(action: :index)
        end

        # iterate through user_ids_arr, and for each user look for a customer. If there's a customer, onboard to billing platform. If not, create a customer and then onboard to billing platform.
        users = ::User.where(id: user_ids_arr)
        onboarded = 0
        users.each do |user|
          verify_customer_created_or_create_customer(user)

          if user.customer.present?
            user.customer.onboard_to_all_billing_platform_products
            onboarded += 1
          end
        end

        flash[:notice] = "You have successfully enqueued #{onboarded} accounts for billing platform onboarding"
        redirect_to(action: :index)
      end

      private

      memoize def user_ids
        params[:new_ids]
      end

      memoize def remaining_count
        params.fetch(:remaining_count, 1).to_i
      end

      memoize def user_ids_arr
        initial_user_ids = user_ids.split(",").map(&:to_i)
      end

      def verify_customer_created_or_create_customer(user)
        user.customer || GitHub::Billing.create_customer(user, {}, actor: @current_user)
      end

      def stafftools_onboarding_staff_required!
        render_404 unless current_user.site_admin?
      end

      def billing_platform_client
        ::Billing::Platform::Api::Client.new
      end

      def onboarded_customers
        customers = Customer.where(billed_via_billing_platform: true).order(:id)
        customers.paginate(page: current_page, per_page: PER_PAGE)
      end
    end
  end
end
