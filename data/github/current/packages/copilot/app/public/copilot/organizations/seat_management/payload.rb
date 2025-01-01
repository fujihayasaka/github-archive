# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      class Payload < ReactPayload::Base
        include GitHub::Memoizer
        include UrlHelpers
        include GitHub::ResilienceMixin
        include MemberFeatureRequestsHelper

        sig { returns(::Organization) }
        attr_reader :organization

        sig { returns(ActionController::Parameters) }
        attr_reader :params

        sig { params(organization: ::Organization, params: ActionController::Parameters, current_user: ::User).void }
        def initialize(organization:, params:, current_user:)
          @organization = organization
          @params = params
          @current_user = T.let(current_user, T.nilable(::User))
        end

        sig { override.returns(String) }
        def route_id
          "copilotForBusinessSeatManagementRoute"
        end

        sig { override.returns(T::Hash[String, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
        def payload
          call.transform_keys(&:to_s)
        end

        sig { returns(Copilot::Types::SeatManagementIndexPayload) }
        def call
          {
            policy: copilot_organization.seat_management_setting,
            seats: {
              seats: seats,
              count: seat_details.count,
              pending_requests: pending_requests,
              licenses: copilot_organization.all_copilot_seats_and_assignments_by_type_and_identifier
            },
            seat_breakdown: Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization).to_object,
            seat_assignments: copilot_organization.seat_assignments.count,
            public_code_suggestions_configured: copilot_organization.public_code_suggestions_configured?,
            business_trial: business_trial&.to_object,
            render_trial_expired_banner: render_trial_expired_banner?,
            render_copilot_insights_banner: render_copilot_insights_banner?,
            business: business,
            can_add_teams: can_add_teams?,
            organization: {
              name: organization.display_login,
              id: organization.id,
              billable: copilot_organization.copilot_billable?,
              has_seat: Copilot::Seat.for_organization(copilot_organization).exists?,
              add_seat_link: add_seat_link,
              copilot_enabled: copilot_organization.copilot_enabled?,
            },
            members_count: organization.members_count,
            can_allow_to_assign_seats_on_business: copilot_organization.can_enable_org_to_assign_seats?(@current_user) && !@current_user&.is_enterprise_managed?,
            plan_text: copilot_organization.copilot_plan.capitalize,
            next_billing_date: copilot_organization.pending_cancellation_date,
            featureRequestInfo: feature_request_info_payload(MemberFeatureRequest::Feature::CopilotForBusiness, @current_user, organization),
            render_pending_downgrade_banner: render_pending_downgrade_banner?,
            display_activity: copilot_organization.display_activity?(seat_details.count),
            adoption_metrics: Copilot::Metrics::Adoption.new(owner: organization).current_payload,
          }
        end

        private

        sig { returns(Copilot::Organization) }
        memoize def copilot_organization
          Copilot::Organization.new(@organization)
        end

        sig { returns(T.nilable(Copilot::Types::BusinessPayload)) }
        memoize def business
          business = organization.business
          return nil unless business

          { name: business.name, slug: business.slug }
        end

        sig { returns(T::Array[Copilot::Organizations::SeatManagement::Detail]) }
        memoize def seat_details
          if copilot_organization.seat_management_enabled_for_selected?
            copilot_organization.seat_assignments(query: query_params.query,
                                                  type: query_params.type,
                                                  sort: query_params.sort,
                                                  direction: query_params.direction)
          else
            copilot_organization.all_org_seat_assignments(query: query_params.query,
                                                          type: query_params.type,
                                                          sort: query_params.sort,
                                                          direction: query_params.direction)
          end
        end

        sig { returns(T::Array[Copilot::Types::SeatPayload]) }
        def seats
          per_page = Orgs::CopilotSettings::SeatManagementController::PER_PAGE
          display_seats = T.must(seat_details.slice((page - 1) * per_page, per_page))
          display_seats.map do |seat_detail|
            assignable_type = seat_detail.seat_assignment.assignable_type
            case assignable_type
            when "User"
              builder = if seat_detail.assignable.nil? || seat_detail.seat_assignment.assignable.nil?
                Copilot::Organizations::SeatManagement::PayloadBuilders::Null
              else
                Copilot::Organizations::SeatManagement::PayloadBuilders::User
              end
              builder.new(seat_detail: seat_detail).call
            when "Team", "OrganizationInvitation", "Organization"
              Copilot::Organizations::SeatManagement::PayloadBuilders
                .const_get(T.cast(assignable_type, String))
                .new(seat_detail: seat_detail)
                .call
            else
              nil
            end
          end.compact
        end

        sig { returns(T.nilable(Copilot::BusinessTrial)) }
        memoize def business_trial
          copilot_organization.business_trial
        end

        sig { returns T::Boolean }
        memoize def can_add_teams?
          @organization.teams.any?
        end

        sig { returns(Copilot::SeatManagement::SeatQuery) }
        memoize def query_params
          Copilot::SeatManagement::SeatQuery.generate(params)
        end

        sig { returns(Integer) }
        memoize def page
          (params[:page] || 1).to_i
        end

        sig { returns(T.any(NilClass, String)) }
        def add_seat_link
          if organization.business && !T.must(organization.business).adminable_by?(@current_user)
            nil
          else
            if organization.business
              enterprise_licensing_path(organization.business, manage_seats: true)
            else
              org_seats_path(organization)
            end
          end
        end

        sig { returns(T.nilable(Copilot::Types::PendingRequestsPayload)) }
        memoize def pending_requests
          with_database_error_fallback(fallback: nil) do
            {
              requesters: pending_requesters,
              count: pending_requests_count,
            }
          end
        end

        sig { returns(T::Array[Copilot::Types::RequesterPayload]) }
        memoize def pending_requesters
          MemberFeatureRequest.requested_member_requests(organization).where(feature: MemberFeatureRequest::Feature::CopilotForBusiness)
            .includes(:requester)
            .limit(100)
            .filter_map do |request|
              next unless requester = request.requester
              {
                id: requester.id,
                display_login: requester.display_login,
                profile_name: requester.profile_name,
                requested_at: request.updated_at,
              }
            end
        end

        sig { returns(Integer) }
        memoize def pending_requests_count
          MemberFeatureRequest.total_for_feature(organization, MemberFeatureRequest::Feature::CopilotForBusiness)
        end

        sig { returns T::Boolean }
        def render_trial_expired_banner?
          return false unless business_trial&.copilot_plan_enterprise? && business_trial&.expired?
          return false if copilot_organization.copilot_plan_enterprise?
          !@current_user&.dismissed_organization_notice?(:copilot_enterprise_trial_expired_banner, copilot_organization.organization_object)
        end

        sig { returns T::Boolean }
        def render_copilot_insights_banner?
          return true unless @current_user.present?
          !@current_user.dismissed_notice?(:copilot_insights_banner)
        end

        sig { returns T::Boolean }
        def render_pending_downgrade_banner?
          return false unless copilot_organization.business.present?
          return false unless copilot_organization.pending_plan_downgrade_date.present?
          copilot_organization.pending_plan_downgrade_date > Date.current
        end
      end
    end
  end
end
