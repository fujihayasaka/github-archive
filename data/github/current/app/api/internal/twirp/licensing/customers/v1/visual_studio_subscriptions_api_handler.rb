# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-customers"
require "google/protobuf/timestamp_pb"

module Api::Internal::Twirp::Licensing
  module Customers
    module V1
      # Handler for the MonolithTwirp::Licensing::Customers::V1::VisualStudioSubscriptionsAPIService
      class VisualStudioSubscriptionsApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Customers::V1::VisualStudioSubscriptionsAPIService

        DEFAULT_VSS_PAGE_SIZE = 100

        def get_visual_studio_subscriptions(req, env)
          unless customer_id = id_argument(req.customer_id)
            return Twirp::Error.invalid_argument("customer_id is required", argument: "customer_id")
          end

          unless customer = Customer.find_by(id: customer_id)
            return Twirp::Error.not_found("customer not found")
          end

          ::Failbot.push "gh.customer.id": customer_id

          unless business = Business.find_by(customer_id: customer.id)
            return Twirp::Error.not_found("business not found")
          end

          page_size = req.page_size > 0 ? req.page_size : DEFAULT_VSS_PAGE_SIZE

          blas, next_page_token = get_bundled_license_assignments(business, req.page_token, page_size)

          user_ids = blas.map(&:user_id).uniq.compact
          users_map = if user_ids.any?
            User.where(id: user_ids).select(:id, :suspended_at).index_by(&:id)
          else
            {}
          end

          response_subscriptions = blas.map do |bla|
            user = users_map[bla.user_id]
            suspended_at = user&.suspended_at

            subscription_args = {
              user_id: bla.user_id,
              subscription_id: bla.subscription_id,
              revoked: bla.revoked,
            }

            if suspended_at
              # Convert ActiveSupport::TimeWithZone to Google::Protobuf::Timestamp
              subscription_args[:user_suspended_at] = Google::Protobuf::Timestamp.new(seconds: suspended_at.to_i)
            end

            MonolithTwirp::Licensing::Customers::V1::VisualStudioSubscription.new(**subscription_args)
          end

          MonolithTwirp::Licensing::Customers::V1::GetVisualStudioSubscriptionsResponse.new(
            visual_studio_subscriptions: response_subscriptions,
            next_page_token:,
          )
        end

        private

        def get_bundled_license_assignments(business, page_token, page_size)
          blas = ::Licensing::BundledLicenseAssignment
            .where(business: business)
            .assigned_user
            .where("id > ?", page_token)
            .order(id: :asc)
            .limit(page_size)
            .to_a

          return [blas, ""] if blas.size == 0

          is_last_page = blas.size < page_size
          next_cursor = is_last_page ? "" : T.must(blas.last).id.to_s

          [blas, next_cursor]
        end
      end
    end
  end
end
