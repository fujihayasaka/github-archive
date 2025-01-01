# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependencyGraph < Service
    ENABLED_KEY = "dependency_graph.enabled".freeze
    DISABLED_KEY = "dependency_graph.disabled".freeze

    # This feature flag is used to determine if public repositories may be disabled,
    # it _does not_ change the default behaviour, we still treat public as on by default
    # and check for absence of the DISABLED_KEY.

    # This feature flag is used to determine if public repositories should be created
    # in a disabled state. It does not change the `enabled?` behaviour, it just ensures that
    # the correct key is set as part of the repository creation orchestration.
    ALWAYS_DEFAULT_OFF_REPO_FLAG = "dependency_graph_off_by_default_public_repos".freeze

    def self.always_default_off_enabled?(repository)
      ::DependencyGraph.check_feature_for_repo_or_owner(repository, ALWAYS_DEFAULT_OFF_REPO_FLAG)
    end

    # These feature flags control the migration of this configuration setting from legacy storage
    # to SecurityProductsEnablement::RepositorySecuritySetting
    CONFIG_MIGRATION_WRITE_NEXT = "dependency_graph_write_config_next".freeze
    CONFIG_MIGRATION_READ_NEXT = "dependency_graph_read_config_next".freeze

    def enabled?
      log_timing do
        # Checks if Dependency Graph is enabled globally
        return false unless GitHub.dependency_graph_enabled?
        return true if GitHub.enterprise?

        if config_next_reads_enabled?
          next_enabled?
        else
          legacy_enabled?
        end
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        # If the repository is archived, we treat this as a noop rather than an error.
        return Result.new(ToggledServiceCollection.empty) if repository.archived?

        legacy_on_enable(actor)
        next_on_enable

        ## get fresh copy of dep manifests by default when setting is enabled.
        unless options[:skip_repository_dependency_manifest_init]
          RepositoryDependencyManifestEnrollJob.perform_later(repository.id, actor_id: actor.id)
        end

        GitHub.instrument("repository_dependency_graph.enable", instrumentation_payload(actor))

        if GitHub.elm_internal_webhooks_enabled?
          GitHub.instrument("repo.advanced_security_settings_update",
            actor: actor,
            repo: repository,
            changes: {
              dependency_graph_enabled: true
            }
          )
        end

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def can_disable?(actor:, options:)
      log_timing do
        vulnerability_alerts = SecurityProduct::VulnerabilityAlerts.new(repository)
        return Result.new(true) unless vulnerability_alerts.enabled?

        # A ghost actor represents an attempt to disable a repository that was deemed inactive.
        # However, a repo with alerts enabled is considered active, and should not be disabled.
        return Result.new(false, "Vulnerability alerts enabled") if actor.ghost?

        vulnerability_alerts.can_disable?(actor: actor, options: options)
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        return Result.new(ToggledServiceCollection.empty) unless enabled?

        dependent_results = disable_dependents(
          :dependency_graph_autosubmit_action,
          :vulnerability_alerts,
          actor: actor,
          options: options)
        return dependent_results if dependent_results.error?

        legacy_on_disable(actor)
        next_on_disable

        RepositoryDependencyClearDependencies.perform_later(
          repository.id,
          actor_id: actor&.id,
          trigger: actor&.ghost? ? :RESET_TRIGGER_MASS_OFFBOARD : :RESET_TRIGGER_REPO_SETTINGS
        )

        GitHub.instrument("repository_dependency_graph.disable", instrumentation_payload(actor))

        if GitHub.elm_internal_webhooks_enabled?
          GitHub.instrument("repo.advanced_security_settings_update",
            actor: actor,
            repo: repository,
            changes: {
              dependency_graph_enabled: false
            }
          )
        end

        Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependent_results.toggled_services))
      end
    end

    def instrumentation_payload(user)
      payload = {
        user: user,
        repo: repository,
      }

      if repository.in_organization?
        payload[:org] = repository.organization
      end

      payload
    end

    def to_sym
      :dependency_graph
    end

    def self.name
      "Dependency graph"
    end

    private

    def legacy_enabled?
      if repository.public? && !repository.fork?
        !repository.config.enabled?(DISABLED_KEY)
      else
        repository.config.enabled?(ENABLED_KEY)
      end
    end

    # We need to make sure that the write feature flag acts as a circuit breaker that disables reading from
    # the new store as it can no longer be trusted as a source of truth if we are missing writes
    def config_next_reads_enabled?
      return false unless ::DependencyGraph.check_feature_for_repo_or_owner(repository, CONFIG_MIGRATION_WRITE_NEXT)

      ::DependencyGraph.check_feature_for_repo_or_owner(repository, CONFIG_MIGRATION_READ_NEXT)
    end

    def next_enabled?
      SecurityProductsEnablement::RepositorySecuritySettings.dependency_graph_enabled?(repository)
    end

    def legacy_on_enable(actor)
      repository.config.enable(ENABLED_KEY, actor)
      repository.config.delete(DISABLED_KEY, actor)
    end

    def next_on_enable
      return unless ::DependencyGraph.check_feature_for_repo_or_owner(repository, CONFIG_MIGRATION_WRITE_NEXT)

      SecurityProductsEnablement::RepositorySecuritySettings.enable_dependency_graph!(repository)
    end

    def legacy_on_disable(actor)
      repository.config.enable(DISABLED_KEY, actor)
      repository.config.delete(ENABLED_KEY, actor)
    end

    def next_on_disable
      return unless ::DependencyGraph.check_feature_for_repo_or_owner(repository, CONFIG_MIGRATION_WRITE_NEXT)

      SecurityProductsEnablement::RepositorySecuritySettings.disable_dependency_graph!(repository)
    end
  end
end
