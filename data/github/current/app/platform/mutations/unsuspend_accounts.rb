# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnsuspendAccounts < Platform::Mutations::Base
      description "Unsuspend a set of accounts."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay id of accounts to unsuspend.", required: true, loads: Platform::Unions::Account
      argument :reason, String, "Reason for unsuspending accounts.", required: true
      argument :origin, String, "The system that performed this classification.", required: false, default_value: "origin_unknown"
      argument :instrument_abuse_classification, Boolean, "Instrument the abuse classification hydro event.", required: false, default_value: true

      field :accounts, [Unions::Account], "The unsuspended accounts.", null: true

      def resolve(accounts:, **inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to unsuspend accounts."
        end

        accounts.each do |account|
          account.unsuspend(
            inputs[:reason],
            actor: context[:viewer],
            instrument_abuse_classification: inputs[:instrument_abuse_classification],
            origin: inputs[:origin],
          )
        end

        { accounts: accounts }
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
