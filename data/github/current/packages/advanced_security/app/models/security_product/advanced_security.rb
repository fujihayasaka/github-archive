# typed: true
# frozen_string_literal: true

module SecurityProduct
  class AdvancedSecurity < Service
    include ::SecretScanning::Features::FeatureFlagHelper

    USER_ENABLED_KEY = "advanced_security.user_enabled"
    def enabled?
      log_timing do
        return false if repository.deleted?
        return false if repository_can_enable_ghas?.error?
        repository.config.enabled?(USER_ENABLED_KEY)
      end
    end

    def purchased_advanced_security?
      repository.advanced_security_configurable?
    end

    def self.blocked_by_connect?
      return false unless GitHub.enterprise?
      GitHub.cache.fetch("SecurityProduct::AdvancedSecurity.blocked_by_connect?/#{GitHub.current_sha}", expires_in: 5.minutes) do
        license = GitHub::Enterprise.license(sync_global_business: false)

        next false unless license.metered_advanced_security?
        # GHES users with metered billing must have GitHub Connect enabled
        next true unless license.github_connect_support? && DotcomConnection.new.is_connected?
        # license sync must also be enabled
        !GitHub.dotcom_user_license_usage_upload_enabled?
      end
    end

    # Can the repository explicitly enable and disable GHAS?
    def repository_can_enable_ghas?
      if GitHub.enterprise?
        if SecurityProduct::AdvancedSecurity.blocked_by_connect?
          return Result.new(false)
        end

        # GHES users can enable GHAS if 'enabled' by the Enterprise
        owner = repository.owner
        if owner&.user?
          ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(owner)
          return Result.new(true) if ghas_for_users.feature_available?
        end
        # If the above check fails, the Enterprise has disallowed enablement for GHES users
        if !owner&.organization?
          return Result.new(false, :advanced_security_requires_an_org)
        end

      else
        # Advanced security is allowed for public repos
        if repository.public?
          return Result.new(false, :advanced_security_enabled_on_public_repo)
        end
      end

      # Has Advanced Security been purchased?
      if purchased_advanced_security?
        return Result.new(true)
      end

      Result.new(false, :advanced_security_not_purchased)
    end

    def can_configure_ghas?
      Result.new(true)
    end

    def can_enable?(actor:, options:)
      log_timing do
        return Result.new(false, :locked_by_metered_usage) if repository.advanced_security_locked_by_metered_usage?

        res = repository_can_enable_ghas?
        return res if !res.value || res.error?

        # Enabling advanced security is restricted by Configurable::AdvancedSecurityAccessPolicy
        unless repository.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL)
          return Result.new(false, :advanced_security_restricted_by_policy)
        end

        if blocked_by_advanced_security_enablement_policy?(actor, options)
          return Result.new(false, :advanced_security_restricted_by_enablement_policy)
        end

        res = can_configure_ghas?
        return res if res.error?

        # Enabling advanced security would exceed seat allowance
        owner = T.must(repository.owner)
        if repository.enforce_advanced_security_committers_limits? && owner.advanced_security_license.enabling_repo_exceeds_seat_allowance?(repository)
          return Result.new(false, :advanced_security_would_exceed_limit)
        end

        Result.new(true)
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        # enable_advanced_security may also turn on TokenScanning
        # independently, depending on the repo's settings
        # on repo if dependabot alerts already enabled

        if repository.config.enable(USER_ENABLED_KEY, actor)
          publish_advanced_security_instrumentation(action: "enabled", actor: actor)

          token_scanning_service = SecurityProduct::TokenScanning.new(repository)
          eligible, _ = token_scanning_service.can_enable?(actor: actor, options: options)

          # If repo getting GHAS enabled is private repo, and has custom rules enabled, we need to reactivate any rules that might have been marked
          # as inactive due to GHAS being previosuly disabled on the repo.
          if repository.dependabot_custom_rules_writable?
            RefreshRuleStateOnGhasEnablementChangeJob.perform_later(repository: repository, ghas_enabled: true)
          end

          # Enable token scanning if configured to
          should_enable_secret_scanning = false
          owner = repository.owner
          if owner&.user?
            should_enable_secret_scanning = SecretScanning::Features::User::TokenScanning.new(owner).secret_scanning_enabled_for_new_repos?

            if biz = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).get_business
              should_enable_secret_scanning ||= SecretScanning::Features::Business::TokenScanning.new(biz).secret_scanning_enabled_for_new_repos?
            end
          end

          already_enabled = token_scanning_service.enabled?

          if eligible && should_enable_secret_scanning
            dependents, error = token_scanning_service.on_enable(actor: actor, options: options)
            Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependents), error)
          elsif already_enabled
            options[:renotify_only] = true
            dependents, error = token_scanning_service.on_enable(actor: actor, options: options)
            Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependents), error)
          else
            Result.new(ToggledServiceCollection.create(to_sym, options))
          end
        else
          Result.new(ToggledServiceCollection.empty)
        end
      end
    end

    def can_disable?(actor:, options:)
      log_timing do
        res = repository_can_enable_ghas?
        return res if res.error?

        if blocked_by_advanced_security_enablement_policy?(actor, options)
          return Result.new(false, :advanced_security_restricted_by_enablement_policy)
        end

        token_scanning = SecurityProduct::TokenScanning.new(repository)
        if token_scanning.enabled? && token_scanning.can_disable?(actor: actor, options: options).error?
          return Result.new(false, :advanced_security_restricted_by_secret_scanning_enablement_policy)
        end

        res = can_configure_ghas?
        return res if res.error?

        Result.new(true)
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        dependents = [:token_scanning]
        dependent_results = disable_dependents(*dependents, actor: actor, options: options)
        return dependent_results if dependent_results.error?

        if repository.config.delete(USER_ENABLED_KEY, actor)
          repository.code_scanning_inactive!

          publish_advanced_security_instrumentation(action: "disabled", actor: actor)
          owner = options[:owner] || repository.owner

          # If repo is getting GHAS disabled, we need to disable all active non-global rules on the repo.
          RefreshRuleStateOnGhasEnablementChangeJob.perform_later(repository: repository, ghas_enabled: false)

          Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependent_results.toggled_services))
        else
          dependent_results
        end
      end
    end

    def publish_advanced_security_instrumentation(action:, actor:)
      payload = {
        actor: actor
      }
      # Repository.instrument doesn't include the link to the business by default
      # but we want it for this event so we have to insert it ourselves
      if GitHub.single_business_environment?
        payload[:business] = GitHub.global_business
      elsif repository.owner&.business.present?
        payload[:business] = repository.owner&.business
      end
      repository.instrument("advanced_security_#{action}", payload)

      GlobalInstrumenter.instrument(
        "advanced_security.#{action}",
        {
          repository_id: repository.id,
          customer_id: payload.dig(:business)&.customer_id
        }
      )
    end

    def to_sym
      :advanced_security
    end

    def self.name
      "Advanced Security"
    end

    def self.error_to_message(symbol)
      case symbol
      when :advanced_security_not_purchased
        "Advanced security has not been purchased."
      when :advanced_security_enabled_on_public_repo
        "Advanced security is always available for public repos."
      when :advanced_security_requires_an_org
        "Advanced security is only available for repositories owned by organizations."
      when :advanced_security_restricted_by_policy
        "Enabling advanced security is restricted by a policy."
      when :advanced_security_would_exceed_limit
        "Enabling advanced security would exceed seat allowance."
      when :advanced_security_restricted_by_enablement_policy
        "An enterprise policy prevented modifying advanced security enablement. Contact your enterprise owner for details."
      when :advanced_security_restricted_by_secret_scanning_enablement_policy
        "An enterprise policy that blocks changes to Secret Scanning enablement prevented modifying advanced security enablement. Contact your enterprise owner for details."
      when :locked_by_metered_usage
        "Advanced security cannot be enabled due to a lock on metered usage."
      else
        super
      end
    end

    private

    # Checks if toggling Advanced Security is restricted by Configurable::AdvancedSecurityEnablementPolicy for the actor
    def blocked_by_advanced_security_enablement_policy?(actor, options)
      return false if options.present? && options[:is_repo_creation]
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_advanced_security_enablement_blocked_by_policy?
    end
  end
end
