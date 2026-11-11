# typed: strict
# frozen_string_literal: true

# User name display configuration concern.
#
# Provides a default implementation for the target for the user name display configuration.
module ApplicationController::UserNameDisplayDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, AbstractController::Helpers::ClassMethods)

    helper_method :target_for_user_name_display_configuration
  end

  class TargetForUserNameDisplayConfigurationMissing < ::StandardError; end

  class UnsetTargetForUserNameDisplayConfiguration
    include Configurable
    include Configurable::UserNameDisplayConfiguration

    sig { override.returns(String) }
    def user_name_display_configuration_value
      raise TargetForUserNameDisplayConfigurationMissing,
        "target_for_user_name_display_configuration must be implemented in the including controller"
    end
  end

  # Override in a controller to return the model that should be queried for user name display configuration, typically
  # the current Organization or Business. If nil is returned, the default configuration will be used.
  sig { returns(T.nilable(Configurable::UserNameDisplayConfiguration)) }
  def target_for_user_name_display_configuration
    UnsetTargetForUserNameDisplayConfiguration.new
  end
end
