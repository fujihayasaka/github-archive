# typed: strict
# frozen_string_literal: true

module Configurable
  module ActionsCustomImagesPolicy
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = T.let("actions_custom_images_policy".freeze, String)

    ALL_ENTITIES = "all"
    SELECTED_ENTITIES = "selected"
    NO_ENTITIES = "none"

    VALUES = T.let([ALL_ENTITIES, SELECTED_ENTITIES, NO_ENTITIES], T::Array[String])
    DEFAULT_VALUE = NO_ENTITIES

    sig { params(actor: ::User).void }
    def enable_custom_images(actor:)
      config.set!(KEY, ALL_ENTITIES, actor)
    end

    sig { params(actor: ::User).void }
    def enable_custom_images_for_selected(actor:)
      config.set!(KEY, SELECTED_ENTITIES, actor)
    end

    sig { params(actor: ::User).void }
    def disable_custom_images(actor:)
      config.set!(KEY, NO_ENTITIES, actor)
    end

    # used for testing
    sig { params(actor: ::User).void }
    def clear_custom_images_policy(actor:)
      config.delete(KEY, actor)
    end

    sig { returns(String) }
    def custom_images_policy
      raw_value = config.get(KEY)
      return raw_value if raw_value.in?(VALUES)
      DEFAULT_VALUE
    end

    sig { returns(T::Boolean) }
    def custom_images_enabled_for_all?
      custom_images_policy == ALL_ENTITIES
    end

    sig { returns(T::Boolean) }
    def custom_images_enabled_for_selected?
      custom_images_policy == SELECTED_ENTITIES
    end

    sig { returns(T::Boolean) }
    def custom_images_disabled?
      custom_images_policy == NO_ENTITIES
    end
  end
end
