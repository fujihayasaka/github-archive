# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-limiter"

module Api::Internal::Twirp::Copilot
  module Limiter
    module V1
      class CopilotLimiterAPIHandler < Api::Internal::Twirp::Handler

        include Api::Internal::Twirp::Copilot::Helpers

        sig do
          params(
            rack_env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).void
        end
        def before_rpc(rack_env, env)
          if (client_key = rack_env[:request_hmac_key])
            env[:client_name] = GitHub.api_internal_twirp_hmac_settings[client_key]
          end
          env[:internal_client_id] = rack_env[:internal_client_id]
          env[:real_ip]            = rack_env["HTTP_X_CLIENT_IP"]
          env[:request_id]         = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
        end

        allow_access_for :client, allowed_clients: %w[
          copilot_limiter
        ]
        handles_service MonolithTwirp::Copilot::Limiter::V1::CopilotLimiterAPIService

        resolve_tenant_context only: [
          :get_consumptive_user,
        ] do |data, _env|
          user = if data.copilot_tracking_id.present?
            ::User.find_by(analytics_tracking_id: data.copilot_tracking_id)
          else
            nil
          end

          next user&.enterprise_managed_business
        end

        # Public: Implementation of the GetConsumptiveUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Limiter::V1::GetConsumptiveUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Limiter::V1::GetConsumptiveUserResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Limiter::V1::GetConsumptiveUserRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def get_consumptive_user(req, env)
          result = load_user(req)
          return result.error unless result.ok?

          copilot_user = Copilot::User.new(result.value!)

          load_consumptive_user_response(copilot_user)
        end

        private

        sig { params(req: T.untyped).returns(GitHub::Result) }
        def load_user(req)
          GitHub.tracer.in_span("copilot.twirp.load_user", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_user") do
              if req.copilot_tracking_id.present?
                # they passed the COPILOT TRACKING ID NOT ANALYTICS
                user = ::User.find_by(analytics_tracking_id: req.copilot_tracking_id)
                return GitHub::Result.new { user } if user

                GitHub.dogstats.increment("copilot.twirp.user_not_found")
                GitHub::Result.error(Twirp::Error.not_found("Copilot Tracking ID '#{req.copilot_tracking_id}' not found."))
              else
                # they didn't pass either
                GitHub.dogstats.increment("copilot.twirp.no_params")
                GitHub::Result.error(Twirp::Error.invalid_argument("must be provided", argument: "id or analytics_tracking_id"))
              end
            end
          end
        end

        GetConsumptiveUserResponse = T.type_alias do
          {
            access_type: Integer,
            business_id: T.nilable(Integer),
            copilot_access_type: T.nilable(String),
            customer_ids: T::Array[Integer],
            id: Integer,
            organization_id: T.nilable(Integer),
            reset_date: T.nilable(MonolithTwirp::Copilot::Limiter::V1::ResetDate),
            copilot_for_business_free: T::Boolean,
            is_staff: T::Boolean,
          }
        end

        sig do
          params(
            copilot_user: Copilot::User,
          ).
          returns(
            GetConsumptiveUserResponse
          )
        end
        def load_consumptive_user_response(copilot_user)
          GitHub.tracer.in_span("copilot.twirp.load_consumptive_user_response", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_consumptive_user_response") do
              public_user = Copilot::Public::User.new(copilot_user.user_object)
              quota_reset_date = copilot_user.quota_reset_date

              # by default, we assume the user has no access or is CFI
              organization_id = T.let(copilot_user.copilot_organizations.first&.id, T.nilable(Integer))
              business_id = T.let(copilot_user.copilot_business&.id, T.nilable(Integer))

              if copilot_user.has_multi_access?
                Copilot::Seat.for_user(copilot_user.user_object).each do |seat|
                  next unless seat.seat_assignment.present?
                  next unless seat.seat_assignment.owner.present?
                  next unless seat.customer_id == copilot_user.billable_customer_id

                  owner = seat.seat_assignment.owner
                  if owner.is_a?(::Organization)
                    organization_id = owner.id
                    if owner.business.present?
                      business_id = T.must(owner.business).id
                    end
                  elsif owner.is_a?(::Business)
                    business_id = owner.id
                  end
                  break
                end
              end

              {
                access_type: twirp_access_type(copilot_user.copilot_authorizer_object_no_snippy.access_type),
                business_id: business_id,
                copilot_access_type: nil,
                customer_ids: public_user.billable_customer_ids.compact,
                id: public_user.user_object.id,
                organization_id: organization_id,
                copilot_for_business_free: copilot_user.copilot_for_business_free?,
                is_staff: copilot_user.user_object.staff_user?,
                reset_date: MonolithTwirp::Copilot::Limiter::V1::ResetDate.new(
                  day: quota_reset_date.day,
                  month: quota_reset_date.month,
                  year: quota_reset_date.year,
                ),
              }
            end
          end
        end
      end
    end
  end
end
