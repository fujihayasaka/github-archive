# typed: true
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningPushProtection < Service
    USER_ENABLED_KEY = "token_scanning_push_protection.user_enabled"

    def initialize(repository)
      super(repository)
      @token_scanning_security_product = SecurityProduct::TokenScanning.new(repository)
      @push_protection = SecretScanning::Features::Repo::PushProtection.new(repository)
    end

    def enabled?(ignore_import: false)
      @push_protection.enabled?(ignore_import:)
    end

    # Enablement of this service depends entirely on TokenScanning being able to be enabled
    def can_enable?(actor:, options:)
      if repository.archived? || repository.deleted?
        Result.new(false, :feature_not_available_on_archived_or_deleted_repos)
      elsif blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      elsif !@token_scanning_security_product.enabled?
        Result.new(false, :token_scanning_disabled)
      else
        Result.new(true)
      end
    end

    def on_enable(actor:, options:)
      @push_protection.enable(actor: actor)

      GitHub.instrument(
        "repository_secret_scanning_push_protection.enable",
        build_instrumentation_payload(actor))

      GlobalInstrumenter.instrument(
        "repository_secret_scanning_push_protection.enable",
        {
          repository_id: repository.id
        }
      )

      GitHub.dogstats.increment("repository_secret_scanning_push_protection.enable", tags: dogstats_tags)
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    def force_enable(actor:, options: {})
      on_enable(actor: actor, options: options)
    end

    def can_disable?(actor:, options:)
      if blocked_by_enterprise_policy?(actor, options)
        Result.new(false, :token_scanning_restricted_by_enablement_policy)
      else
        Result.new(true)
      end
    end

    def on_disable(actor:, options:)
      dependent_results = disable_dependents(:token_scanning_delegated_bypass, actor: actor, options: options)
      return dependent_results if dependent_results.error?

      @push_protection.disable(actor: actor)

      GitHub.instrument(
        "repository_secret_scanning_push_protection.disable",
        build_instrumentation_payload(actor))

      GlobalInstrumenter.instrument(
        "repository_secret_scanning_push_protection.disable",
        {
          repository_id: repository.id
        }
      )

      GitHub.dogstats.increment("repository_secret_scanning_push_protection.disable", tags: dogstats_tags)
      SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repository)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    def force_disable(actor:, options: {})
      on_disable(actor: actor, options: options)
    end

    def to_sym
      :token_scanning_push_protection
    end

    def self.name
      "Secret Scanning Push Protection"
    end

    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_disabled
        "Push protection can only be changed on repositories with secret scanning enabled."
      when :token_scanning_restricted_by_enablement_policy
        "Modifying secret scanning and push protection has been blocked by an enterprise policy. Contact your enterprise owner for details."
      else
        super
      end
    end

    private

    def dogstats_tags
      [
        "visibility:#{repository.visibility}",
        "ghas_secret_scanning:#{SecretScanning::Features::Repo::Capabilities.new(repository).ghas_secret_scanning?}",
      ]
    end

    def build_instrumentation_payload(actor)
      payload = {
        user: actor,
        repo: repository
      }

      if repository.in_organization?
        payload[:org] = repository.organization
      end

      payload
    end

    # Checks if toggling push protection is restricted by Configurable::SecretScanningSettingsPolicy
    def blocked_by_enterprise_policy?(actor, options)
      return false if options.present? && options[:is_repo_creation]
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_secret_scanning_settings_blocked_by_policy?
    end
  end
end
