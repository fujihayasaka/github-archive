# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class LicensifyCustomerController < BusinessBaseController
      include ::Licensing::Licensify

      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
        Stafftools::Businesses::LicensifyCustomerController#sync_customer
      ].freeze

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Ballast,
        only: [:show, :sync_customer]

      def show
        @customer_data = fetch_customer_data
        render "stafftools/businesses/licensify_customer/show", locals: {
          this_business: this_business,
          customer_data: @customer_data,
          error: @customer_error,
          customer_not_found: @customer_not_found,
        }
      end

      def sync_customer # rubocop:todo GitHub/UseRestfulActions
        UpdateCustomerInLicensifyJob.perform_later(this_business.customer_id)

        flash[:notice] = "Enqueued job to synchronize customer to Licensify"
        redirect_to stafftools_licensify_customer_path(this_business)
      end

      private

      def fetch_customer_data
        return nil unless this_business.customer_id

        req = ::Licensify::Services::V1::GetCustomerRequest.new(
          customerId: this_business.customer_id,
        )
        res = licensify_client.get_customer(req)

        if res.error.present?
          if res.error.code == :not_found || res.error.msg&.include?("does not exist")
            @customer_not_found = true
          else
            @customer_error = res.error.msg
          end
          return nil
        end

        res.data.customer
      rescue Faraday::Error, Twirp::Error => e
        @customer_error = e.message
        nil
      end
    end
  end
end
