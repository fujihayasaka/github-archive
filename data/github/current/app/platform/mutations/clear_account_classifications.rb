# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ClearAccountClassifications < Platform::Mutations::Base
      description "Clear account classification."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay ids of accounts to clear.", required: true
      argument :origin, String, "The system that performed this classification.", required: false, default_value: "origin_unknown"

      field :accounts, [Unions::Account], "The unclassified accounts.", null: true
      argument :instrument_abuse_classification, Boolean, "Instrument the abuse classification hydro event.", required: false, default_value: true

      def resolve(**inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to clear account classification."
        end

        account_promises = inputs[:account_ids].map do |gid|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id \
            Platform::Unions::Account.possible_types, gid, context
        end

        Promise.all(account_promises).then do |accounts|
          accounts.each do |account|
            account.mark_not_spammy(
              actor: context[:viewer],
              whitelist: false,
              origin: inputs[:origin],
              instrument_abuse_classification: inputs[:instrument_abuse_classification],
            )
          end

          { accounts: accounts }
        end.sync
      end

      def can_access?
        (
          self.class.viewer_is_site_admin?(context[:viewer], self.class.name) &&
          SpamuraiNextAccess.user_has_permission?(login: context[:viewer].login, permission: "actions-clear-classification")
        )
      end
    end
  end
end
