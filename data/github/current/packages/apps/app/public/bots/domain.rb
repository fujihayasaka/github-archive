# typed: strict
# frozen_string_literal: true

module Bots
  class Domain < GH::Domain::Base
    # Public: Find the Bot associated with the given token. The returned Bot has
    # its installation context set to the installation associated with the given
    # token. The installation context determines the Bot's permissions (i.e.,
    # which actions it can take on which Repositories).
    #
    # value                   - The String token value.
    # push_token_to_audit_log - The Boolean switch to determine whether to add
    #                           token context to the Audit Log. (default false).
    # is_retry                - The Boolean tag to give our stats more context
    #                           about retries. (default false).
    #
    # Returns a Bot or nil.
    sig do
      params(
        value: T.nilable(String),
        push_token_to_audit_log: T::Boolean,
        is_retry: T::Boolean
      ).returns(T.nilable(Bot))
    end
    def from_unhashed_token(value, push_token_to_audit_log: false, is_retry: false)
      return if value.blank?

      hashed_value = ServerToServerTokens::Domain.hash_token(value)
      token_record = ServerToServerTokens.domain.by_unhashed_token(value)

      role_tag  = ActiveRecord::Base.connected_to?(role: :reading) ? "role:reading" : "role:writing"
      retry_tag = "is_retry:#{is_retry}"

      if push_token_to_audit_log
        # This Audit context addition catches integration token uses which are different from logged_in sessions
        Audit.context.push(token_id: token_record&.id)
        # For stateless tokens, also push the UUID for traceability
        Audit.context.push(stateless_token_id: token_record.token_id) if token_record&.is_a?(StatelessAuthenticationToken)
      end

      if token_record.nil?
        GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
          "result:failure", "reason:token_missing", role_tag, retry_tag
        ])

        return
      end

      if token_record.hashed_value != hashed_value
        GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
          "result:failure", "reason:token_mismatch", role_tag, retry_tag
        ])

        return
      end

      authenticatable = token_record.authenticatable_class.find_by(id: token_record.authenticatable_id)
      authenticatable_type_tag = "authenticatable_type:#{token_record.authenticatable_type.underscore}"

      if authenticatable.nil?
        GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
          "result:failure", "reason:authenticatable_missing",
          authenticatable_type_tag, role_tag, retry_tag
        ])

        return
      end

      case authenticatable
      when ScopedIntegrationInstallation
        parent = authenticatable.parent

        # A ScopedIntegrationInstallation's parent should never be nil.
        #
        # If it is, it's due to replication lag. This sets the parent to what it
        # should be so that we can continue the request.
        #
        # See https://github.com/github/github/issues/142265 for further details.
        if parent.nil?
          # Exit early if we are on the primary and can't find the parent.
          if ActiveRecord::Base.connected_to?(role: :writing)
            GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
              "result:failure", "reason:parent_installation_missing",
              authenticatable_type_tag, role_tag, retry_tag
            ])

            return
          end

          parent_from_primary =
            ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
              IntegrationInstallation.find_by(id: authenticatable.integration_installation_id)
            end

          # If we fail to find the parent, the request can't continue.
          if parent_from_primary.nil?
            GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
              "result:failure", "reason:parent_installation_missing",
              authenticatable_type_tag, role_tag, retry_tag
            ])

            return
          end

          authenticatable.parent = parent_from_primary
        end
      end

      if !authenticatable.valid_for_current_tenant?
        GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
          "result:failure", "reason:mismatch_tenant", role_tag,
          authenticatable_type_tag, retry_tag
        ])

        # If it's not valid for the current tenant, fail out.
        return
      end

      bot = authenticatable.bot

      if bot.nil?
        GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
          "result:failure", "reason:bot_missing", role_tag,
          authenticatable_type_tag, retry_tag
        ])

        return
      end

      GitHub.dogstats.increment("bots.domain.from_unhashed_token", tags: [
        "result:success", role_tag, retry_tag, authenticatable_type_tag
      ])

      bot
    end
  end
end
