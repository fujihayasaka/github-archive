# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SuspendAccounts < Platform::Mutations::Base
      docs_category :meta
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
        description: "When suspending an organization, also suspend its owners. Superseded by suspendMemberUsers."
      argument :suspend_member_users, Boolean, required: false,
        description: "When suspending an organization or enterprise, also suspend all member users. Supersedes suspendOrgOwners."
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

          # Protected accounts must not seed cascade expansion either —
          # cascading off ghost / [bot] would suspend their incidental
          # orgs / owners / members (availability#5523).
          next if Spam::ProtectedAccounts.protected?(account)

          if account.organization? && inputs[:suspend_org_owners]
            suspend_accounts(
              accounts: account.admins,
              inputs: inputs,
              reason: "#{inputs[:reason]} - flagged with organization",
            )
          end
          if account.organization? && inputs[:suspend_member_users]
            suspend_accounts(
              accounts: User.where(id: account.member_ids),
              inputs: inputs,
              reason: "#{inputs[:reason]} - member of suspended organization",
            )
          end
          if account.user? && inputs[:suspend_owned_orgs]
            suspend_accounts(
              accounts: account.owned_organizations,
              inputs: inputs,
              reason: "#{inputs[:reason]} - flagged with owner",
            )
          end
          if account.is_a?(Business) && inputs[:suspend_member_users]
            if account.sales_managed?
              raise Errors::Forbidden.new \
                "Cannot suspend member users of a sales-served enterprise."
            end
            user_ids = account.all_member_user_ids
            suspend_accounts(
              accounts: User.where(id: user_ids),
              inputs: inputs,
              reason: "#{inputs[:reason]} - member of suspended enterprise",
            )
          end
        end

        { accounts: accounts }
      end

      def suspend_accounts(accounts:, inputs:, reason:)
        account_ids = accounts.pluck(:id)
        GitHub::BatchedScope.batched(values: account_ids, batch_size: 100) do |slice|
          User.where(id: slice).each do |account|
            if Spam::ProtectedAccounts.protected?(account)
              log_protected_skip(account, skip_reason: "protected_account_cascade", suspend_reason: reason)
              next
            end

            if skip_as_high_profile?(account)
              log_protected_skip(account, skip_reason: "cascade_high_profile", suspend_reason: reason)
              next
            end

            suspend_account(
              account: account,
              inputs: inputs,
              reason: reason
            )
          end
        end
      end

      def suspend_account(account:, inputs:, reason:)
        if Spam::ProtectedAccounts.protected?(account)
          log_protected_skip(account, skip_reason: "protected_account", suspend_reason: reason)
          return
        end

        zendesk_ticket_fields = DsaConstants.extract_zendesk_ticket_fields(inputs[:dsa]&.zendesk_ticket_url)
        if inputs[:dsa]&.zendesk_ticket_url.present? && zendesk_ticket_fields.nil?
          raise Errors::Validation.new("Zendesk ticket URL must be a valid Zendesk agent ticket URL for an allowed GitHub Zendesk subdomain")
        end

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
          zendesk_ticket_id: zendesk_ticket_fields&.dig(:zendesk_ticket_id),
          zendesk_subdomain: zendesk_ticket_fields&.dig(:zendesk_subdomain),
          notes: inputs[:notes],
        )
      end

      private

      # Returns true if `account` should be skipped from a cascade as
      # high-profile. Memoized per invocation; fails safe (treats account
      # as HP) on HP-check error.
      #
      # EMU-scoped accounts are exempt — HighProfileSignals treats
      # TRUSTED-tier billable ownership as HP, and every EMU enterprise
      # is TRUSTED, which would no-op every EMU cascade (the headline
      # use case for this mutation).
      def skip_as_high_profile?(account)
        return false if emu_scoped?(account)

        cache = (@skip_as_high_profile_cache ||= {})
        return cache[account.id] if cache.key?(account.id)

        result = HighProfileSignals.high_profile_user?(account)
        cache[account.id] = !!(result && result.first)
      rescue StandardError => e
        GitHub.logger.warn(
          "code.namespace" => "Platform::Mutations::SuspendAccounts",
          "code.function" => "skip_as_high_profile?",
          "gh.user.id" => account.id,
          "error.message" => e.message,
          "error.class" => e.class.name,
          "message" => "High-profile check raised; failing safe and treating account as cascade-protected",
        )
        (@skip_as_high_profile_cache ||= {})[account.id] = true
      end

      # True for EMU users (User#is_enterprise_managed?) and EMU-tenant
      # orgs (Organization#enterprise_managed_user_enabled?, since
      # Organization#is_enterprise_managed? always returns false).
      def emu_scoped?(account)
        return !!account.is_enterprise_managed? if account.user?
        return !!account.enterprise_managed_user_enabled? if account.organization?
        false
      end

      def log_protected_skip(account, skip_reason:, suspend_reason:)
        GitHub.logger.warn(
          "code.namespace" => "Platform::Mutations::SuspendAccounts",
          "code.function" => "log_protected_skip",
          "gh.user.id" => account.id,
          "gh.user.type" => account.class.name,
          "actor.id" => context[:viewer]&.id,
          "suspend.skip_reason" => skip_reason,
          "suspend.reason" => suspend_reason,
          "message" => "Skipped suspend of protected account",
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
