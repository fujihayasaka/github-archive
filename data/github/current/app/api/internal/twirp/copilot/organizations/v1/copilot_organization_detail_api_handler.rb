# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-organizations"

module Api::Internal::Twirp::Copilot
  module Organizations
    module V1
      # Handler for the MonolithTwirp::Copilot::Organizations::V1::CopilotOrganizationDetailAPIService
      class CopilotOrganizationDetailAPIHandler < Api::Internal::Twirp::Handler

        allow_access_for :client, allowed_clients: %w[copilot_usage_service copilot_api sweagentd]
        handles_service MonolithTwirp::Copilot::Organizations::V1::CopilotOrganizationDetailAPIService

        # Public: Implementation of the GetCopilotOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def get_copilot_organization(req, env)
          # we need an id or and analytics_tracking_id
          unless (req.id.present? && req.id.nonzero?) || req.analytics_tracking_id.present?
            return Twirp::Error.invalid_argument("must be provided", argument: "id or analytics_tracking_id")
          end

          organization = load_organization(req)
          return Twirp::Error.not_found("Organization ID '#{req.id}' not found.") unless organization

          copilot_organization = Copilot::Organization.new(organization)
          load_single_response(copilot_organization)
        end

        # Public: Implementation of the GetCopilotOrganizationsByAnalyticTrackingIds Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationsByAnalyticTrackingIdsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationsByAnalyticTrackingIdsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationsByAnalyticTrackingIdsRequest,
            env: T::Hash[T.untyped, T.untyped] # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def get_copilot_organizations_by_analytic_tracking_ids(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "analytics_tracking_ids") unless req.analytics_tracking_ids.present?
          {
            organization_details: load_multiple_responses(req.analytics_tracking_ids.map(&:to_s)),
          }
        end

        private

        CopilotOrganizationMinimalDetails = T.type_alias do
          {
            analytics_tracking_id: T.nilable(String),
            are_metrics_enabled: T.nilable(T::Boolean),
            business_id: T.nilable(Integer),
            display_login: T.nilable(String),
            id: T.nilable(Integer),
          }
        end

        GetCopilotOrganizationsByAnalyticTrackingIdsResponse = T.type_alias do
          {
            organization_details: T.nilable(CopilotOrganizationMinimalDetails)
          }
        end

        SeatBreakdown = T.type_alias do
          {
            seats_assigned: T.nilable(Integer),
            seats_billed: T.nilable(Integer),
            seats_pending: T.nilable(Integer)
          }
        end

        CopilotOrganizationDetails = T.type_alias do
          {
            analytics_tracking_id: T.nilable(String),
            are_metrics_enabled: T.nilable(T::Boolean),
            business_id: T.nilable(Integer),
            chat_enabled: T.nilable(T.any(Symbol, Integer)),
            copilot_billing_type: T.nilable(String),
            copilot_enabled: T.nilable(T.any(Symbol, Integer)),
            id: T.nilable(Integer),
            mobile_chat: T.nilable(T.any(Symbol, Integer)),
            on_free_trial: T.nilable(T::Boolean),
            public_code_suggestions: T.nilable(T.any(Symbol, Integer)),
            seat_break_down: T.nilable(SeatBreakdown),
            seat_management: T.nilable(T.any(Symbol, Integer)),
          }
        end

        GetCopilotOrganizationResponse = T.type_alias do
          {
            organization_details: T.nilable(CopilotOrganizationDetails)
          }
        end

        sig do
          params(
            copilot_organization: Copilot::Organization
          ).
          returns(
            GetCopilotOrganizationResponse
          )
        end
        def load_single_response(copilot_organization)
          {
            organization_details: {
              analytics_tracking_id: copilot_organization.analytics_tracking_id,
              are_metrics_enabled: copilot_organization.telemetry_aggregation_enabled?,
              business_id: copilot_organization.copilot_business&.id,
              chat_enabled: load_copilot_editor_chat_setting(copilot_organization),
              copilot_billing_type: copilot_organization.copilot_billing_type,
              copilot_enabled: load_copilot_enabled_setting(copilot_organization),
              id: copilot_organization.id,
              mobile_chat: load_copilot_mobile_chat_setting(copilot_organization),
              on_free_trial: copilot_organization.on_free_trial?,
              public_code_suggestions: load_copilot_snippy_setting(copilot_organization),
              seat_break_down: load_seat_break_down(copilot_organization),
              seat_management: nil,
            }
          }
        end

        sig do
          params(
            analytic_tracking_ids: T::Array[String]
          ).
          returns(
            T::Array[CopilotOrganizationMinimalDetails]
          )
        end
        def load_multiple_responses(analytic_tracking_ids)
          ::Organization.where(analytics_tracking_id: analytic_tracking_ids).inject([]) do |memo, organization|
            memo << {
              analytics_tracking_id: organization.analytics_tracking_id,
              are_metrics_enabled: Copilot::Organization.new(organization).telemetry_aggregation_enabled?,
              business_id: organization.business&.id,
              display_login: organization.display_login,
              id: organization.id
            } if organization

            memo
          end
        end

        sig { params(copilot_organization: Copilot::Organization).returns(SeatBreakdown) }
        def load_seat_break_down(copilot_organization)
          break_down = Copilot::Organizations::SeatManagement::SeatBreakdown.new(copilot_organization.organization_object)
          {
            seats_assigned: break_down.seats_assigned,
            seats_billed: break_down.seats_billed,
            seats_pending: break_down.seats_pending,
          }
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_editor_chat_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_ENABLED if copilot_organization.chat_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_DISABLED if copilot_organization.chat_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_NO_POLICY if copilot_organization.no_chat_policy?
          return MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_UNCONFIGURED unless copilot_organization.chat_enabled_configured?
          MonolithTwirp::Copilot::Organizations::V1::Chat::CHAT_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_mobile_chat_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::MobileChat::MOBILE_CHAT_ENABLED if copilot_organization.mobile_chat_enabled?
          return MonolithTwirp::Copilot::Organizations::V1::MobileChat::MOBILE_CHAT_DISABLED if copilot_organization.mobile_chat_disabled?
          MonolithTwirp::Copilot::Organizations::V1::MobileChat::MOBILE_CHAT_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_enabled_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::CopilotSetting::COPILOT_SETTING_DISABLED if copilot_organization.copilot_disabled?
          return MonolithTwirp::Copilot::Organizations::V1::CopilotSetting::COPILOT_SETTING_ENABLED if copilot_organization.copilot_enabled?
          MonolithTwirp::Copilot::Organizations::V1::CopilotSetting::COPILOT_SETTING_INVALID
        end

        sig { params(copilot_organization: Copilot::Organization).returns(Integer) }
        def load_copilot_snippy_setting(copilot_organization)
          return MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_UNCONFIGURED unless copilot_organization.public_code_suggestions_configured?
          return MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_ALLOWED if copilot_organization.allow_public_code_suggestions?
          return MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_BLOCKED if copilot_organization.block_public_code_suggestions?
          MonolithTwirp::Copilot::Organizations::V1::PublicCodeSuggestions::PUBLIC_CODE_SUGGESTIONS_INVALID
        end

        sig { params(req: MonolithTwirp::Copilot::Organizations::V1::GetCopilotOrganizationRequest).returns(T.nilable(::Organization)) }
        def load_organization(req)
          if req.id.present? && req.id.nonzero?
            ::Organization.find_by(id: req.id)
          elsif req.analytics_tracking_id.present?
            ::Organization.find_by(analytics_tracking_id: req.analytics_tracking_id)
          else
            nil
          end
        end
      end
    end
  end
end
