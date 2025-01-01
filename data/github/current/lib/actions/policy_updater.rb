# typed: false
# frozen_string_literal: true

class Actions::PolicyUpdater
  DISABLED = "disabled"

  VALID_OPTIONS = [
    Configurable::ActionsAccess::ALL_ENTITIES,
    Configurable::ActionsAccess::SELECTED_ENTITIES,
    Configurable::ActionsAccess::NO_ENTITIES,
    DISABLED,
  ]

  def self.perform(**options)
    new(**options).perform
  end

  def initialize(entity:, policy:, actor:)
    @entity = entity
    @policy = policy
    @old_policy = entity.actions_access
    @actor = actor
  end

  def perform
    update_settings
    instrument_changes
  end

  private

  def update_settings
    case @policy
    when Configurable::ActionsAccess::ALL_ENTITIES
      @entity.enable_actions(actor: @actor)
    when Configurable::ActionsAccess::SELECTED_ENTITIES
      @entity.enable_actions_for_selected(actor: @actor)
    when Configurable::ActionsAccess::NO_ENTITIES, DISABLED
      @entity.disable_actions(actor: @actor)
    end
  end

  def instrument_changes
    return unless @entity.actions_access != @old_policy
    @entity.instrument "update_actions_settings",
      actor:                 @actor,
      new_policy:            @entity.actions_access,
      old_policy:            @old_policy,
      updated_access_policy: true
  end
end
