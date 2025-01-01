# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SuspendAccounts < Platform::Mutations::Base
      description "Suspend a set of accounts."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay id of accounts to suspend.", required: true, loads: Platform::Unions::Account
      argument :reason, String, "Reason for suspending accounts.", required: true
      argument :origin, String, "The system that performed this classification.", required: false, default_value: "origin_unknown"
      argument :hard_flag, Boolean, "Suspend even if the account is hammy.", required: false
      argument :instrument_abuse_classification, Boolean, "Instrument the abuse classification hydro event.", required: false, default_value: true
      argument :dsa, Inputs::DsaAccountModerationAction, "The DSA account moderation fields.", required: false
      argument :notes, String, "Additional suspension notes to be included in the audit log", required: false
      argument :suspend_owned_orgs, Boolean, required: false,
        description: "When suspending a user, also suspend all owned organizations."
      argument :suspend_org_owners, Boolean, required: false,
        description: "When suspending an organization, also suspend its owners."
      field :accounts, [Unions::Account], "The suspended accounts.", null: true

      def resolve(accounts:, **inputs)
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to suspend accounts."
        end

        accounts.each do |account|
          suspend_account(
            account: account,
            inputs: inputs,
            reason: inputs[:reason]
          )
          if account.organization? && inputs[:suspend_org_owners]
            suspend_accounts(
              accounts: account.admins,
              inputs: inputs,
              reason: "#{inputs[:reason]} - flagged with organization",
            )
          end
          if account.user? && inputs[:suspend_owned_orgs]
            suspend_accounts(
              accounts: account.owned_organizations,
              inputs: inputs,
              reason: "#{inputs[:reason]} - flagged with owner",
            )
          end
        end

        { accounts: accounts }
      end

      def suspend_accounts(accounts:, inputs:, reason:)
        accounts.in_batches(of: 100) do |batch|
          batch.each do |account|
            suspend_account(
              account: account,
              inputs: inputs,
              reason: reason
            )
          end
        end
      end

      def suspend_account(account:, inputs:, reason:)
        account.suspend(
          reason,
          actor: context[:viewer],
          hard_flag: inputs[:hard_flag],
          instrument_abuse_classification: inputs[:instrument_abuse_classification],
          origin: inputs[:origin],
          dsa_source: inputs[:dsa]&.dsa_source,
          dsa_countries: inputs[:dsa]&.dsa_countries,
          moderation_end_timestamp: inputs[:dsa]&.moderation_end_timestamp,
          content_creation_date: inputs[:dsa]&.content_creation_date,
          content_formats: inputs[:dsa]&.content_formats,
          items_reported_to_ncmec: inputs[:dsa]&.items_reported_to_ncmec,
          notes: inputs[:notes],
        )
      end

      def can_access?
        (
          self.class.viewer_is_site_admin?(context[:viewer], self.class.name) &&
          # disabled rubocop because context[:viewer].login is used to compare staff permissions and the value is not shown to the user
          SpamuraiNextAccess.user_has_permission?(login: context[:viewer].login, permission: "actions-suspend") # rubocop:disable GitHub/DoNotAllowLogin
        )
      end
    end
  end
end
