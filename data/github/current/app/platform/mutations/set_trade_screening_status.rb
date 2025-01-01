# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetTradeScreeningStatus < Platform::Mutations::Base
      visibility :internal, environments: [:dotcom]
      description "Sets the trade screening status for an account."

      minimum_accepted_scopes ["site_admin"]

      argument :screening_profile_id, ID, "The global relay id of the screening profile record to update.", required: true, loads: Objects::AccountScreeningProfile
      argument :status, String, "The new status to set for the screening profile", required: true
      argument :reason, String, "The reason for manually setting the status", required: true

      field :account_screening_profile, Objects::AccountScreeningProfile, "The screening profile that the status was set for.", null: true

      def resolve(screening_profile:, **inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to set trade screening status."
        end

        raise Errors::Unprocessable.new "Invalid screening status." if AccountScreeningProfile::VALID_SDN_STATUSES.exclude?(inputs[:status].to_sym)

        status_reason = { "status_reason": inputs[:reason] }
        update_hash = {
          msft_trade_screening_status: inputs[:status],
          metadata: screening_profile.metadata.merge(status_reason),
        }
        if screening_profile.update(update_hash)
          { account_screening_profile: screening_profile }
        else
          raise Errors::Unprocessable.new("Could not set trade screening status. Errors: #{screening_profile.errors.full_messages.to_sentence}")
        end
      end

      def can_access?
        (
          self.class.viewer_is_site_admin?(context[:viewer], self.class.name) &&
          SpamuraiNextAccess.user_has_permission?(login: context[:viewer].display_login, permission: "can-execute-trade-controls")
        )
      end
    end
  end
end
