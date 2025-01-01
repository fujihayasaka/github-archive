# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    class Adoption
      include GitHub::Memoizer

      # We're using a rolling 28 day window for each period to determine activity. This means that if a seat has auth
      # or activity up to 28 days prior to a period, it will be considered authed or active for that period
      LOOKBACK_DAYS = 28

      sig { returns(::Organization) }
      attr_reader :owner

      sig { params(owner: ::Organization).void }
      def initialize(owner:)
        @owner = owner
      end

      sig { returns(Copilot::Types::CurrentAdoptionMetricsPayload) }
      def current_payload
        unless owner_can_view_metrics?
          return null_current_payload
        end

        seats = Copilot::Seat.for_owner(owner).pluck(:id)
        recent_authentications = Copilot::Authentication.for_organization(owner).where(authentication_at: LOOKBACK_DAYS.days.ago..).pluck(:copilot_seat_id)
        recent_activities = Copilot::Activity.for_organization(owner).where(activity_at: LOOKBACK_DAYS.days.ago..).pluck(:copilot_seat_id)

        {
          total: seats.count,
          active: recent_activities.count,
          inactive: (recent_authentications - recent_activities).count,
          dormant: (seats - recent_authentications).count,
        }
      end

      private

      sig { returns(T::Boolean) }
      def owner_can_view_metrics?
        if FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, owner, default: false) ||
          FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, owner.business, default: false)
          return false unless Copilot::Organization.new(owner).insights_enabled?
        end

        owner.feature_flag_enabled?(:copilot_metrics_access_page_updates, default: false) || !!owner.business&.feature_flag_enabled?(:copilot_metrics_access_page_updates, default: false)
      end

      sig { returns(Copilot::Types::CurrentAdoptionMetricsPayload) }
      def null_current_payload
        { total: 0, active: 0, inactive: 0, dormant: 0 }
      end
    end
  end
end
