# typed: strict
# frozen_string_literal: true

module Configurable
  module ActionsCustomImagesAllowedByOwner
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = T.let("actions_custom_images_allowed_by_owner".freeze, String)

    sig { params(actor: ::User).void }
    def allow_custom_images(actor:)
      config.enable(KEY, actor)
    end

    sig { params(actor: ::User).void }
    def disallow_custom_images(actor:)
      config.disable(KEY, actor)
    end

    # used for testing
    sig { params(actor: ::User).void }
    def clear_custom_images_allowed(actor:)
      config.delete(KEY, actor)
    end

    # This means that the setting has to be explicitly set to `true` in order to
    # be considered enabled. `nil` is equivalent to `false`. Inherited values are ignored.
    sig { returns(T::Boolean) }
    def custom_images_allowed_by_owner?
      !!config.local?(KEY) && config.enabled?(KEY)
    end
  end
end
