# typed: strict
# frozen_string_literal: true


###
# CodeSecurity provides explicit enablement for Code Scanning and related features.
#
# Enabling this does not mean that Code Scanning is actively analysing a repository, this is a pre-requisite in the
# same way that Code Scanning UI in the bundled SKU is currently gated by GHAS being enabled/disabled.
#
# It has a 1:1 mapping to the Code Scanning SKU, and is the gate for all functionality that is bundled
# with it (at time of writing GHAS minus Secret Scanning).
#
# Customers using bundled GHAS will not interact with this service, but continue to interact with AdvancedSecurity.
#
# Sub-products under the Code Scanning SKU could be automatically disabled if this service is disabled. See TokenScanning
# for an example of this.
#
module SecurityProduct
  class CodeSecurity < Service
    include GitHub::Memoizer
    include SecretScanning::Features::FeatureFlagHelper

    USER_ENABLED_KEY = "code_security.user_enabled"

    # TODO add log_timing blocks around method bodies... Type checker was complaining so I left that for later

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      if ::CodeSecurity::Features::AdvancedSecurityHelper.code_security_metered_usage_locked?(repository: repository)
        return Result.new(false, :locked_by_metered_usage)
      end

      if repository.advanced_security_products_bundled?
        # If billing is bundled the Code Security service is not used.
        # But we allow it to be enabled to prepare for a transition to unbundled billing
        # if GHAS is enabled.
        return Result.new(true) if SecurityProduct::AdvancedSecurity.new(repository).enabled?
        return Result.new(false, :code_security_requires_advanced_security_when_bundled)
      end

      res = repository_can_enable_code_security
      return res if !res.value || res.error?

      return Result.new(false, :code_security_not_allowed_by_policy) unless repository.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY)

      return Result.new(false, :code_security_restricted_by_enablement_policy) if blocked_by_code_security_enablement_policy?(actor, options)

      return Result.new(false, :code_security_would_exceed_limit) if repository.owner&.code_security&.enabling_repo_exceeds_seat_allowance?(repository)

      Result.new(true)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      return Result.new(false, :code_security_restricted_by_enablement_policy) if blocked_by_code_security_enablement_policy?(actor, options)

      Result.new(true)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      if repository.config.enable(USER_ENABLED_KEY, actor)

        payload = { user: actor, repo: repository }

        if repository.in_organization?
          payload[:org] = repository.organization
        end

        GitHub.instrument("repository_code_security.enable", payload)

        GlobalInstrumenter.instrument("repository_code_security.enable", { repository_id: repository.id })

        RefreshRuleStateOnGhasEnablementChangeJob.perform_later(repository: repository, ghas_enabled: true)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      else
        Result.new(ToggledServiceCollection.empty)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      dependent_results = Result.new(ToggledServiceCollection.empty)
      begin
        dependent_results = disable_dependents(:auto_codeql, actor: actor, options: options)
      rescue CodeScanning::AutoCodeqlError => e
        # We disable auto_codeql separately because we want to do it on a best-effort basis. If it fails, it's not huge deal.
        Failbot.report(e)
      end

      if repository.config.delete(USER_ENABLED_KEY, actor)
        payload = { user: actor, repo: repository }

        if repository.in_organization?
          payload[:org] = repository.organization
        end

        GitHub.instrument("repository_code_security.disable", payload)

        GlobalInstrumenter.instrument("repository_code_security.disable", { repository_id: repository.id })

        RefreshRuleStateOnGhasEnablementChangeJob.perform_later(repository: repository, ghas_enabled: false)

        Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependent_results.toggled_services))
      else
        Result.new(ToggledServiceCollection.empty)
      end
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      return false if repository.deleted?
      return false if repository_can_enable_code_security.error?
      repository.config.enabled?(USER_ENABLED_KEY)
    end

    sig { override.returns(Symbol) }
    def to_sym
      :code_security
    end

    sig { override.returns(String) }
    def self.name
      "Code Security"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :code_security_not_purchased
        "Code Security has not been purchased."
      when :code_security_requires_advanced_security_when_bundled
        "When billing is bundled Code Security can only be enabled if Advanced Security is enabled."
      when :code_security_requires_an_org
        "Code Security is only available for repositories owned by organizations."
      when :code_security_enabled_on_public_repo
        "Code Security is always available for public repos."
      when :code_security_would_exceed_limit
        "Enabling Code Security would exceed seat allowance."
      when :code_security_not_allowed_by_policy
        "An enterprise policy prevented modifying Code Security enablement. Contact your enterprise owner for details."
      when :code_security_restricted_by_enablement_policy
        "Code Security cannot be enabled due to an enterprise policy."
      when :locked_by_metered_usage
        "Code Security cannot be enabled due to a lock on metered usage."
      else
        super
      end
    end

    # Can the repository explicitly enable and disable Code Security?
    sig { returns(SecurityProduct::Result) }
    def repository_can_enable_code_security
      if GitHub.enterprise?
        if SecurityProduct::CodeSecurity.blocked_by_connect?
          return Result.new(false)
        end

        # Code Security is only available for organizations
        if repository.owner.nil? || !repository.owner&.organization?
          return Result.new(false, :code_security_requires_an_org)
        end

      else
        # Code Security features are available for free for public repos
        if repository.public?
          return Result.new(false, :code_security_enabled_on_public_repo)
        end
      end

      # Has Code Security been purchased?
      if purchased_code_security?
        return Result.new(true)
      end

      Result.new(false, :code_security_not_purchased)
    end

    sig { returns(T::Boolean) }
    def self.blocked_by_connect?
      return false unless GitHub.enterprise?
      GitHub.cache.fetch("SecurityProduct::CodeSecurity.blocked_by_connect?/#{GitHub.current_sha}", expires_in: 5.minutes) do
        license = GitHub::Enterprise.license(sync_global_business: false)

        next false unless license.metered_code_security?
        # GHES users with metered billing must have GitHub Connect enabled
        next true unless license.github_connect_support? && DotcomConnection.new.is_connected?
        # license sync must also be enabled
        !GitHub.dotcom_user_license_usage_upload_enabled?
      end
    end

    private

    sig { returns(T::Boolean) }
    def purchased_code_security?
      if repository.owner&.organization?
        repository.owner&.code_security_purchased? || false
      else
        false
      end
    end

    sig { params(actor: User, options: T.untyped).returns(T::Boolean) }
    def blocked_by_code_security_enablement_policy?(actor, options)
      return false if options.present? && options[:is_repo_creation]
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_code_security_enablement_blocked_by_policy?
    end
  end
end
