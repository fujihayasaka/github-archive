# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ClassifyAccountsAsHammy < Platform::Mutations::Base
      description "Classify a set of accounts as hammy."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay id of accounts to classify hammy.", required: true, loads: Unions::Account
      argument :origin, String, "The system that performed this classification.", required: false, default_value: "origin_unknown"
      argument :rule_name, String, "The rule that performed this classification.", required: false
      argument :rule_version, String, "The rule that performed this classification.", required: false
      argument :classify_owned_orgs_as_hammy, Boolean, required: false,
        description: "When classifying a user as Hammy, also classify all their owned organizations as Hammy."

      field :accounts, [Unions::Account], "The accounts marked hammy.", null: true
      argument :instrument_abuse_classification, Boolean, "Instrument the abuse classification hydro event.", required: false, default_value: true

      def resolve(accounts:, **inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to classify accounts hammy."
        end

        accounts.each do |account|
          account.mark_as_hammy(
            actor: context[:viewer],
            origin: inputs[:origin],
            instrument_abuse_classification: inputs[:instrument_abuse_classification],
            rule_name: inputs[:rule_name],
            rule_version: inputs[:rule_version],
          )

          if account.user? && inputs[:classify_owned_orgs_as_hammy]
            classify_accounts(
              accounts: account.owned_organizations,
              inputs: inputs,
              instrument_abuse_classification: true,
              hammy_reason: "#{inputs[:reason]} - flagged hammy with owner",
            )
          end
        end

        { accounts: accounts }
      end

      def classify_accounts(accounts:, inputs:, instrument_abuse_classification:, hammy_reason:)
        accounts.in_batches(of: 100) do |batch|
          batch.each do |account|
            account.mark_as_hammy({
              actor: context[:viewer],
              reason: hammy_reason,
              origin: inputs[:origin],
              hard_flag: inputs[:hard_flag],
              instrument_abuse_classification: instrument_abuse_classification,
            })
          end
        end
      end

      def can_access?
        (
          self.class.viewer_is_site_admin?(context[:viewer], self.class.name) &&
          SpamuraiNextAccess.user_has_permission?(login: context[:viewer].login, permission: "actions-classify-hammy")
        )
      end
    end
  end
end
