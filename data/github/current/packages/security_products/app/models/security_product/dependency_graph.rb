# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependencyGraph < Service
    ENABLED_KEY = "dependency_graph.enabled".freeze
    DISABLED_KEY = "dependency_graph.disabled".freeze

    def enabled?
      log_timing do
        # Checks if Dependency Graph is enabled globally
        return false unless GitHub.dependency_graph_enabled?
        return true if GitHub.enterprise?

        if repository.public? && !repository.fork?
          !repository.config.enabled?(DISABLED_KEY)
        else
          repository.config.enabled?(ENABLED_KEY)
        end
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        # If the repository is archived, we treat this as a noop rather than an error.
        return Result.new(ToggledServiceCollection.empty) if repository.archived?

        repository.config.enable(ENABLED_KEY, actor)
        repository.config.delete(DISABLED_KEY, actor)

        ## get fresh copy of dep manifests by default when setting is enabled.
        unless options[:skip_repository_dependency_manifest_init]
          RepositoryDependencyManifestInitializationJob.perform_later(repository.id)
        end

        GitHub.instrument("repository_dependency_graph.enable", instrumentation_payload(actor))

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def can_disable?(actor:, options:)
      log_timing do
        return Result.new(false, "Cannot disable on public repos") if repository.public?

        vulnerability_alerts = SecurityProduct::VulnerabilityAlerts.new(repository)
        return Result.new(true) unless vulnerability_alerts.enabled?

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

        repository.config.enable(DISABLED_KEY, actor)
        repository.config.delete(ENABLED_KEY, actor)

        RepositoryDependencyClearDependencies.perform_later(repository.id)

        GitHub.instrument("repository_dependency_graph.disable", instrumentation_payload(actor))

        Result.new(ToggledServiceCollection.create(to_sym, options).merge!(dependent_results.value))
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
  end
end
