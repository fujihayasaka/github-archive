# typed: true
# frozen_string_literal: true

module Configurable
  # Stores ELM (Enterprise Live Migration) migration state on a source repository
  # so the appropriate banner can be rendered at each phase.
  #
  # State values match the migrations-vnext RepositoryState enum:
  #   started           - migration has begun; source repo is still editable
  #   resources_sent    - resources are being copied; source repo is still editable
  #   locked            - cutover has begun; source repo is archived / read-only
  #   live_updates_sent - final updates are being synced; source repo is archived / read-only
  #   complete          - migration is finished; source repo remains archived
  module RepositoryElmMigrationState
    STATE_PREFIX = "repository.elm_migration_state"
    DESTINATION_URL_PREFIX = "repository.elm_migration_destination_url"

    EDITABLE_STATES = %w[started resources_sent].freeze
    CUTOVER_STATES = %w[locked live_updates_sent].freeze
    COMPLETE_STATE = "complete"
    ALL_STATES = (EDITABLE_STATES + CUTOVER_STATES + [COMPLETE_STATE]).freeze

    # Public: Returns true if this repository is an ELM migration source.
    def elm_migration_source?
      ALL_STATES.include?(config.get(elm_migration_state_config_key))
    end

    # Public: Returns the current ELM migration state string, or nil if not set.
    def elm_migration_state
      return nil unless elm_migration_source?
      config.get(elm_migration_state_config_key)
    end

    # Public: Returns the full destination URL stored alongside the migration state, or nil.
    def elm_migration_destination_url
      config.get(elm_migration_destination_url_config_key)
    end

    # Public: Returns true when the source repo is in an editable pre-cutover state.
    def elm_migration_editable?
      EDITABLE_STATES.include?(elm_migration_state)
    end

    # Public: Returns true when cutover has started and the source repo is read-only.
    def elm_migration_in_cutover?
      CUTOVER_STATES.include?(elm_migration_state)
    end

    # Public: Returns true when the migration is complete.
    def elm_migration_complete?
      elm_migration_state == COMPLETE_STATE
    end

    # Public: Stores the ELM migration state on the repository.
    #
    # state           - one of ALL_STATES
    # destination_url - the full URL to the destination repository (optional)
    # actor           - the actor making the change (defaults to owner)
    #
    # Raises ArgumentError if state is not a recognised value.
    def set_elm_migration_state(state, destination_url: nil, actor: configuration_owner)
      unless ALL_STATES.include?(state)
        raise ArgumentError, "state must be one of #{ALL_STATES.join(", ")}. Got: #{state}"
      end

      config.set!(elm_migration_state_config_key, state, actor)

      if destination_url.present?
        config.set!(elm_migration_destination_url_config_key, destination_url, actor)
      end
    end

    # Public: Removes all ELM migration state from the repository.
    def clear_elm_migration_state(actor: configuration_owner)
      config.delete(elm_migration_state_config_key, actor)
      config.delete(elm_migration_destination_url_config_key, actor)
    end

    private

    def elm_migration_state_config_key
      STATE_PREFIX
    end

    def elm_migration_destination_url_config_key
      DESTINATION_URL_PREFIX
    end
  end
end
