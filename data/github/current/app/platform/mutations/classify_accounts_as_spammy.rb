# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ClassifyAccountsAsSpammy < Platform::Mutations::Base
      description "Classify a set of accounts as spammy."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay id of accounts to classify spammy.", required: true
      argument :reason, String, "Reason for marking accounts spammy.", required: true
      argument :hard_flag, Boolean, "Hard flag accounts as spammy.", required: false
      argument :suspend, Boolean, "Suspend accounts.", required: false
      argument :classify_owned_orgs_as_spammy, Boolean, required: false,
        description: "When classifying/suspending a user, also classify/suspend all owned organizations."
      argument :classify_org_owners_as_spammy, Boolean, required: false,
        description: "When classifying/suspending an organization, also classify/suspend its owners."
      argument :origin, String, "The system that performed this classification.", required: false, default_value: "origin_unknown"
      argument :rule_name, String, "The rule that performed this classification.", required: false
      argument :rule_version, String, "The rule that performed this classification.", required: false
      argument :instrument_abuse_classification, Boolean, "Instrument the abuse classification hydro event.", required: false, default_value: true
      argument :dsa, Inputs::DsaAccountModerationAction, "The DSA account moderation fields.", required: false
      argument :notes, String, "Additional notes to be included in the audit log and staffnotes", required: false

      field :accounts, [Unions::Account], "The accounts marked spammy.", null: true

      def resolve(**inputs)
        start = Time.now
        unless can_access?
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to classify accounts spammy."
        end

        account_promises = inputs[:account_ids].map do |gid|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id \
            Platform::Unions::Account.possible_types, gid, context
        end

        num_accounts = 0
        return_value = Promise.all(account_promises).then do |accounts|
          accounts.each do |account|
            num_accounts += 1
            classify_suspend_account(
              account: account,
              inputs: inputs,
              instrument_abuse_classification: inputs[:instrument_abuse_classification],
              spammy_reason: inputs[:reason],
            )

            if account.organization? && inputs[:classify_org_owners_as_spammy]
              num_accounts += classify_suspend_accounts(
                accounts: account.admins,
                inputs: inputs,
                instrument_abuse_classification: true,
                spammy_reason: "#{inputs[:reason]} - flagged with organization",
              )
            end

            if account.user? && inputs[:classify_owned_orgs_as_spammy]
              num_accounts += classify_suspend_accounts(
                accounts: account.owned_organizations,
                inputs: inputs,
                instrument_abuse_classification: true,
                spammy_reason: "#{inputs[:reason]} - flagged with owner",
              )
            end
          end

          { accounts: accounts }
        end.sync

        tags = []
        if inputs[:classify_org_owners_as_spammy]
          tags << "org_related_accounts_flag:classify_org_owners_as_spammy"
        elsif inputs[:classify_owned_orgs_as_spammy]
          tags << "org_related_accounts_flag:classify_owned_orgs_as_spammy"
        end
        duration = 1000 * (Time.now - start)
        duration_per_account = duration / num_accounts
        GitHub.dogstats.distribution("classify_accounts_as_spammy_mutation.duration_per_account", duration_per_account, tags: tags)
        GitHub.dogstats.distribution("classify_accounts_as_spammy_mutation.num_accounts", num_accounts, tags: tags)

        return_value
      end

      def classify_suspend_accounts(accounts:, inputs:, instrument_abuse_classification:, spammy_reason:)
        num_accounts = 0
        accounts.in_batches(of: 100) do |batch|
          batch.each do |account|
            num_accounts += 1
            classify_suspend_account(
              account: account,
              inputs: inputs,
              instrument_abuse_classification: instrument_abuse_classification,
              spammy_reason: spammy_reason,
            )
          end
        end
        num_accounts
      end

      # Classify and maybe suspend the account.
      def classify_suspend_account(account:, inputs:, instrument_abuse_classification:, spammy_reason:)
        # Grab existing statuses so we can decide if we need to send an abuse classification event.
        not_previously_spammy = !account.spammy?
        not_previously_suspended = !account.suspended?
        serialized_previous_classification = ::Hydro::EntitySerializer.account_spammy_classification(account)
        serialized_previous_spammy_reason = ::Hydro::EntitySerializer.account_spammy_reason(account)
        serialized_previously_suspended = ::Hydro::EntitySerializer.account_suspended(account)

        dsa_source = inputs[:dsa]&.dsa_source
        dsa_countries = inputs[:dsa]&.dsa_countries
        moderation_type = inputs[:dsa]&.moderation_type
        moderation_end_timestamp = inputs[:dsa]&.moderation_end_timestamp
        content_creation_date = inputs[:dsa]&.content_creation_date
        content_formats = inputs[:dsa]&.content_formats

        account.mark_as_spammy({
          actor: context[:viewer],
          reason: spammy_reason,
          origin: inputs[:origin],
          hard_flag: inputs[:hard_flag],
          instrument_abuse_classification: false,
          dsa_source: inputs[:dsa]&.dsa_source,
          dsa_countries: inputs[:dsa]&.dsa_countries,
          moderation_end_timestamp: inputs[:dsa]&.moderation_end_timestamp,
          content_creation_date: inputs[:dsa]&.content_creation_date,
          content_formats: inputs[:dsa]&.content_formats,
          items_reported_to_ncmec: inputs[:dsa]&.items_reported_to_ncmec,
          notes: inputs[:notes],
        })

        if inputs[:suspend]
          account.suspend(
            spammy_reason,
            actor: context[:viewer],
            hard_flag: inputs[:hard_flag],
            instrument_abuse_classification: false,
            dsa_source: inputs[:dsa]&.dsa_source,
            dsa_countries: inputs[:dsa]&.dsa_countries,
            moderation_end_timestamp: inputs[:dsa]&.moderation_end_timestamp,
            content_creation_date: inputs[:dsa]&.content_creation_date,
            content_formats: inputs[:dsa]&.content_formats,
            items_reported_to_ncmec: inputs[:dsa]&.items_reported_to_ncmec,
            notes: inputs[:notes],
          )
        end

        classification_changed = account.spammy? && not_previously_spammy
        suspended_status_changed = account.suspended? && not_previously_suspended

        # If the status has changed and we want to instrument these events, then send them.
        # instrument_abuse_classification being false means that another service has published the event.
        if (classification_changed || suspended_status_changed) && instrument_abuse_classification
          event = if account.is_a?(::Business)
            "enterprise_abuse_classification.publish"
          else
            "abuse_classification.publish"
          end
          payload = {
            actor: context[:viewer],
            origin: inputs[:origin],
            queue_action: :QUEUE_ACTION_NONE,
            rule_name: inputs[:rule_name],
            rule_version: inputs[:rule_version],
            serialized_previous_classification: serialized_previous_classification,
            serialized_previous_spammy_reason: serialized_previous_spammy_reason,
            serialized_previously_suspended: serialized_previously_suspended
          }
          if account.is_a?(::Business)
            payload[:business] = account
          else
            payload[:account] = account
          end

          GlobalInstrumenter.instrument event, payload
        end
      end

      def can_access?
        (
          self.class.viewer_is_site_admin?(context[:viewer], self.class.name) &&
          SpamuraiNextAccess.user_has_permission?(login: context[:viewer].login, permission: "actions-classify-spammy")
        )
      end
    end
  end
end
