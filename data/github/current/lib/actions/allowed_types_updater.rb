# typed: false
# frozen_string_literal: true

class Actions::AllowedTypesUpdater
  ALL = "all"
  SELECTED = "selected"
  LOCAL_ONLY = "local_only"

  def self.perform(**options)
    new(**options).perform
  end

  def initialize(entity:, policy:, actor:)
    @entity = entity
    @policy = policy
    @old_policy = entity.actions_allowlist
    @actor = actor
  end

  def perform
    update_settings
    instrument_changes
  end

  private

  def update_settings
    case @policy
    when ALL
      @entity.clear_allowlist_settings
    when LOCAL_ONLY
      @entity.enable_local_actions_only
    when SELECTED
      # The only way to represent the "SELECTED" selection is to set
      # `github_owned_allowed` or `verified_allowed` to true. This isn't ideal since
      # users may not actually want this to be predetermined for them. Until we have
      # a system in place to represent ALL vs. LOCAL_ONLY vs. SELECTED, this
      # workaround will do for the time-being.
      @entity.enable_specified_actions_only(github_owned: true, actor: @actor)
    end
  end

  def instrument_changes
    return if @entity.reload.actions_allowlist == @old_policy

    @entity.instrument "update_actions_settings",
      actor:                  @actor,
      new_policy:             @policy,
      updated_allowed_types:  true
  end

  def enabled_for_selected?
    return @_enabled_for_selected if defined?(@_enabled_for_selected)
    @_enabled_for_selected = @entity.actions_enabled_for_selected_entities?
  end
end
