# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependencyGraphAutosubmitAction < Service
    include SecurityProduct::Service::ActionsChecks

    class Options < SecurityProduct::Service::Options
      option :labeled_runners, default: false
      validates :labeled_runners, inclusion: {
        in: [true, false],
        message: "Automatic dependency submission must have the labeled runners option set to true or false."
      }
    end

    CONFIG_KEY = "auto_dependencies_submit".freeze
    # TODO: Rename label in the database
    #
    # This key name doesn't align with the constant as we shipped this as 'self-hosted' prior to
    # incorporating better support for GitHub-hosted large runners.
    #
    # When we look at moving our configuration keys out of the shared KV table, it would be useful
    # to rename this opportunistically during the migration.
    LABELLED_CONFIG_KEY = "dependency_graph_auto_dependencies_self_hosted".freeze
    EVENT_KEY = "dependency_graph.auto_dependencies_submit".freeze

    ACTIONS_RUNNER_LABEL = "dependency-submission"

    ERROR_MESSAGE_NO_ACTIONS = "Automatic dependency submission cannot be enabled because actions are disabled".freeze
    ERROR_MESSAGE_NO_LABELLED_RUNNERS = "No runner groups with the label '#{ACTIONS_RUNNER_LABEL}' are attached to this Repository".freeze

    ENABLEMENT_VALUES = [
      DISABLED = "disabled",
      ENABLED_CLOUD = "enabled_cloud",
      ENABLED_SELF_HOSTED = "enabled_self_hosted"
    ].freeze

    def visible?
      config_prerequisites_met?
    end

    def available_in_security_configuration?
      GitHub.dependency_graph_autosubmit_action_enabled?
    end

    def enabled?
      log_timing do
        return false unless config_prerequisites_met?

        repository.config.enabled?(CONFIG_KEY)
      end
    end

    def enabled_with_options?(options: {})
      log_timing do
        return false unless config_prerequisites_met?

        if options[:labeled_runners]
          repository.config.enabled?(CONFIG_KEY) && repository.config.enabled?(LABELLED_CONFIG_KEY)
        else
          repository.config.enabled?(CONFIG_KEY) && !repository.config.enabled?(LABELLED_CONFIG_KEY)
        end
      end
    end

    def labeled_runners_enabled?
      log_timing do
        return false unless config_prerequisites_met?

        repository.config.enabled?(LABELLED_CONFIG_KEY)
      end
    end

    def labeled_runners_available?
      return false unless repository.dependency_graph_enabled?

      actions_runner_checker.labelled_runners_available?(desired_labels: [ACTIONS_RUNNER_LABEL])
    end

    def can_enable?(actor:, options:)
      log_timing do
        return Result.new(false, :disabled_for_instance) unless GitHub.dependency_graph_autosubmit_action_enabled?
        return Result.new(false, :dependency_graph_disabled) unless repository.dependency_graph_enabled?

        if repository.actions_disabled?
          repository.errors.add(:base, ERROR_MESSAGE_NO_ACTIONS)
          return Result.new(false, :actions_disabled)
        end

        if options[:labeled_runners]
          unless actions_runner_checker.labelled_runners_available?(desired_labels: [ACTIONS_RUNNER_LABEL])
            repository.errors.add(:base, ERROR_MESSAGE_NO_LABELLED_RUNNERS)
            return Result.new(false, :no_runners_assigned)
          end
        end

        Result.new(true)
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        repository.config.enable(CONFIG_KEY, actor)

        initial_label_state = repository.config.enabled?(LABELLED_CONFIG_KEY)

        if options[:labeled_runners]
          new_label_state = true
          repository.config.enable(LABELLED_CONFIG_KEY, actor)
        else
          new_label_state = false
          repository.config.delete(LABELLED_CONFIG_KEY, actor)
        end

        # If the feature has gone from enabled to enabled with labels, or vice versa,
        # we should force any attached security configuration to be removed since
        # its feature-specific options no longer apply.
        if initial_label_state != new_label_state
          attempt_to_force_remove_security_configuration
        end

        GlobalInstrumenter.instrument(EVENT_KEY, instrumentation_payload(actor, true, options[:labeled_runners]))

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        repository.config.delete(CONFIG_KEY, actor)
        repository.config.delete(LABELLED_CONFIG_KEY, actor)

        GlobalInstrumenter.instrument(EVENT_KEY, instrumentation_payload(actor, false, false))

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def to_sym
      :dependency_graph_autosubmit_action
    end

    def self.name
      "Automatic dependency submission"
    end

    def self.error_to_message(symbol)
      case symbol
      when :actions_disabled
        "Automatic dependency submission can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it."
      when :no_runners_assigned
        "Automatic dependency submission can only be enabled if runners with label #{ACTIONS_RUNNER_LABEL} are assigned to this repository."
      when :dependency_graph_disabled
        "Automatic dependency submission can only be enabled if Dependency graph is enabled. Please enable Dependency graph for this repository."
      when :disabled_for_instance
        "Automatic dependency submission is not available."
      else
        super
      end
    end

    private

    # This method collects up all our configuration points that must be met for convienance:
    # - The feature must be enabled for this GitHub instance, which is always true for non-GHES envs
    # - The feature-flag for autosubmission is enabled in this environment
    # - Finally, the repository has already enabled Dependency Graph.
    def config_prerequisites_met?
      return false unless GitHub.dependency_graph_autosubmit_action_enabled?

      repository.dependency_graph_enabled?
    end

    def instrumentation_payload(actor, enrolled, self_hosted)
      payload = {
        actor: actor,
        repositories: [repository],
      }
      payload[:enrollment_status] = enrolled ? :ENROLLED : :NOT_ENROLLED
      payload[:runner_type] = self_hosted ? :SELF_HOSTED : :CLOUD

      payload
    end

    def attempt_to_force_remove_security_configuration
      if repository.owner&.security_configurations_enabled?
        repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: repository.id)
        repository_security_configuration&.remove_if_possible(
          action: "enabled",
          feature: to_sym,
          owner: T.must(repository.owner),
          force: true,
        )
      end
    end
  end
end
