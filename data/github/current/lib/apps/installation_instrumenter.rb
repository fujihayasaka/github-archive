# typed: true
# frozen_string_literal: true

# Wrapper for instrumentation emitted by GitHub Apps to allow custom
# configurations for Internal Apps
module Apps
  class InstallationInstrumenter

    DEFAULT_CREATE_EVENT_KEY = "integration_installation.create"
    DEFAULT_SCOPED_CREATE_EVENT_KEY = "scoped_integration_installation.create"
    DEFAULT_REPOS_ADDED_EVENT_KEY = "integration_installation.repositories_added"
    DEFAULT_REPOS_REMOVED_EVENT_KEY = "integration_installation.repositories_removed"
    DEFAULT_DELETE_EVENT_KEY = "integration_installation.destroy"

    def initialize(installation)
      @installation = installation
      @integration = installation.integration
    end

    def instrument_creation(payload, instrumentation_config)
      event_config = Apps::Privileged.custom_instrumentation_event(:create_installation, @integration) || DEFAULT_CREATE_EVENT_KEY

      if GitHub.flipper[:instrument_installation_creation_with_repo_ids].enabled?
        payload[:repository_ids] =
          if payload[:repository_selection] == "selected" && instrumentation_config[:repositories].present?
            instrumentation_config[:repositories].pluck(:id)
          else
            []
          end
      end

      instrument event_config, payload, instrumentation_config: instrumentation_config
    end

    def instrument_scoped_creation(payload)
      event_config = Apps::Privileged.custom_instrumentation_event(:create_scoped_installation, @integration) || DEFAULT_SCOPED_CREATE_EVENT_KEY

      instrument event_config, payload
    end

    def instrument_repositories_added(payload, configurations)
      event_config = Apps::Privileged.custom_instrumentation_event(:repositories_added, @integration) || DEFAULT_REPOS_ADDED_EVENT_KEY

      instrument event_config, payload, instrumentation_config: configurations
    end

    def instrument_repositories_removed(payload, configurations)
      event_config = Apps::Privileged.custom_instrumentation_event(:repositories_removed, @integration) || DEFAULT_REPOS_REMOVED_EVENT_KEY

      instrument event_config, payload, instrumentation_config: configurations
    end

    def instrument_deletion(payload)
      event_config = Apps::Privileged.custom_instrumentation_event(:delete_installation, @integration) || DEFAULT_DELETE_EVENT_KEY

      instrument event_config, payload
    end

    private

    # This keeps compatibility with capabilities that skipped
    # the audit log. New audit log events will be introduced
    # in a follow up, hopefully removing the need for this
    def skip_instrumentation?(event_config)
      event_config == :skip
    end

    def instrument(event_config, payload, instrumentation_config: nil)
      return if skip_instrumentation?(event_config)

      instrumentation_values =
        # Allow for callables to be passed in from the Internal Apps
        # registry, taking as params:
        #  - the installation
        #  - a hash of configs passed through from the model
        #
        # and returning a hash with two keys:
        #  - `event_key`, a string for the instrumentation key
        #  - `event_payload`, an array of payloads to be instrumented
        if event_config.respond_to?(:call)
          event_config.call(@installation, instrumentation_config) || {}
        else
          {
            event_key: event_config,
            event_payloads: [payload]
          }
        end

      return if instrumentation_values.empty?

      # We loop over payloads because some internal apps instrument
      # multiple events on one action i.e. actions and codespaces
      # emit a create event for every selected repo instead of one
      # create event with all selected repos listed
      instrumentation_values[:event_payloads].each do |payload|
        GitHub.instrument instrumentation_values[:event_key], payload
      end
    end
  end
end
