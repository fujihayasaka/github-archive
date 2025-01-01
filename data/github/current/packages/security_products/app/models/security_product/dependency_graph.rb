# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependencyGraph < Service
    def enabled?
      log_timing do
        # Checks if Dependency Graph is enabled globally
        return false unless GitHub.dependency_graph_enabled?
        return true if GitHub.enterprise?

        SecurityProductsEnablement::RepositorySecuritySettings.dependency_graph_enabled?(repository)
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        # If the repository is archived, we treat this as a noop rather than an error.
        return Result.new(ToggledServiceCollection.empty) if repository.archived?

        SecurityProductsEnablement::RepositorySecuritySettings.enable_dependency_graph!(repository)

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

        # A staff user actor represents an attempt to disable a repository that was deemed inactive.
        if actor.staff_user?
          result = staff_offboarding_check
          return result if result.error?
        end

        vulnerability_alerts.can_disable?(actor: actor, options: options)
      end
    end

    def can_delete_orphaned?
      log_timing do
        # Should not be considered an orphaned repository if the dependency graph is enabled.
        return Result.new(false, "Dependency graph enabled") if enabled?

        # Ensure vulnerability alerts and updates are disabled, as they may
        # mysteriously remain active independently of the dependency graph.
        staff_offboarding_check
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

        SecurityProductsEnablement::RepositorySecuritySettings.disable_dependency_graph!(repository)

        RepositoryDependencyClearDependencies.perform_later(
          repository.id,
          actor_id: actor&.id,
          trigger: actor&.staff_user? ? :RESET_TRIGGER_MASS_OFFBOARD : :RESET_TRIGGER_REPO_SETTINGS
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

    # Staff offboarding events are blocked by explicit use of Dependabot features, so this method performs some
    # specific checks on the feature chain beyond Dependabot Graph that we consider blocking.
    def staff_offboarding_check
      # A repo with alerts explicitly enabled by the user is considered active, and should not be disabled.
      return Result.new(false, "Vulnerability alerts enabled") if vulnerability_alerts_explicitly_enabled?
      # If vulnerability alerts are not enabled explicitly, we check if updates are in use.
      vulnerability_updates = SecurityProduct::VulnerabilityUpdates.new(repository)
      return Result.new(false, "Vulnerability updates enabled") if vulnerability_updates.enabled?

      # If neither are feature is on, then we are ok to proceed.
      Result.new(true)
    end

    def vulnerability_alerts_explicitly_enabled?
      repository.config.enabled?(SecurityProduct::VulnerabilityAlerts::ENABLED_KEY)
    end
  end
end
