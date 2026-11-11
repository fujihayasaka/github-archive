# typed: strict
# frozen_string_literal: true

class Actions::CustomImagesPolicyUpdater

  VALID_OPTIONS = T.let([
    Configurable::ActionsCustomImagesPolicy::ALL_ENTITIES,
    Configurable::ActionsCustomImagesPolicy::SELECTED_ENTITIES,
    Configurable::ActionsCustomImagesPolicy::NO_ENTITIES,
  ], T::Array[String])

  sig { params(option: String).returns(T::Boolean) }
  def self.is_valid_option?(option)
    VALID_OPTIONS.include?(option)
  end

  sig { params(options: T.untyped).void }
  def self.perform(**options)
    new(**T.unsafe(options)).perform
  end

  sig { params(entity: ::Business, policy: String, actor: ::User).void }
  def initialize(entity:, policy:, actor:)
    @entity = entity
    @policy = policy
    @old_policy = T.let(entity.custom_images_policy, String)
    @actor = actor
  end

  sig { void }
  def perform
    update_settings
    instrument_changes
  end

  private

  sig { void }
  def update_settings
    case @policy
    when Configurable::ActionsCustomImagesPolicy::ALL_ENTITIES
      @entity.enable_custom_images(actor: @actor)
    when Configurable::ActionsCustomImagesPolicy::SELECTED_ENTITIES
      @entity.enable_custom_images_for_selected(actor: @actor)
    when Configurable::ActionsCustomImagesPolicy::NO_ENTITIES
      @entity.disable_custom_images(actor: @actor)
    end
  end

  sig { void }
  def instrument_changes
    return unless @entity.custom_images_policy != @old_policy
    @entity.instrument "update_custom_images_policy",
      actor:                 @actor,
      new_policy:            @entity.custom_images_policy,
      old_policy:            @old_policy
  end
end
