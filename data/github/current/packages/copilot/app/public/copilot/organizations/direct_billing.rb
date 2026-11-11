# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module DirectBilling
      include Copilot::Organizations::Signatures
      include Copilot::Organizations::FeatureEnabled

      extend T::Helpers

      abstract!

      # Checks whether this org or its parent enterprise has any Copilot seats,
      # which determines eligibility for direct org billing features.
      # Gated by the :copilot_api_s2s_require_cbce feature flag.
      sig { returns(T::Boolean) }
      def has_copilot_seats_for_direct_billing?
        return true unless feature_flag_enabled?(:copilot_api_s2s_require_cbce, default: false)
        return true if has_assigned_seats?

        business = organization_object.business
        if business
          Copilot::Organizations::DirectBilling.enterprise_has_copilot_seats?(business)
        else
          false
        end
      end

      # Checks whether any organization under the enterprise has seats,
      # or if the enterprise itself directly owns seats.
      sig { params(business: ::Business).returns(T::Boolean) }
      def self.enterprise_has_copilot_seats?(business)
        # NOTE: `organization_ids` materializes the ids in Ruby. We can't use a
        # subquery here (e.g. `business.organizations.select(:id)`) because the
        # `organizations` association joins through tables in a different
        # database than `copilot_seats`, which MySQL can't subquery across.
        return true if Copilot::Seat.where(organization_id: business.organization_ids).exists?
        return true if Copilot::Seat.for_owner(business).exists?

        false
      end

      # Shared editability helper for direct-org-billing policies. Returns true
      # when the entity (Business or Organization) has Copilot seats and is
      # therefore eligible to edit direct-org-billing policies. When the
      # `:copilot_api_s2s_require_cbce` flag is disabled, returns true so the
      # check is a no-op.
      sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
      def self.has_copilot_seats_for_entity?(entity)
        return true unless entity.feature_flag_enabled?(:copilot_api_s2s_require_cbce, default: false)

        case entity.sorbet_class.to_s
        when "Business"
          enterprise_has_copilot_seats?(T.cast(entity, Copilot::Business).business_object)
        when "Organization"
          T.cast(entity, Copilot::Organization).has_copilot_seats_for_direct_billing?
        else
          false
        end
      end
    end
  end
end
