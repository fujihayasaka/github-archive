# typed: strict
# frozen_string_literal: true

class MemexProject
  module DisplayNameDependency
    extend T::Helpers

    requires_ancestor { MemexProject }

    # Returns the user_name_display_configuration_value for the memex owner, falling back to the default of HANDLE
    # if unsupported.
    sig { returns(T.nilable(String)) }
    def owner_user_name_display_configuration_value
      owner = self.owner
      return Configurable::UserNameDisplayConfiguration::HANDLE unless owner.respond_to?(:user_name_display_configuration_value)

      owner.user_name_display_configuration_value
    end

    # Returns true if the memex owner's current user_name_display_configuration value requires user profile data
    # to render display names, false otherwise.
    sig { returns(T::Boolean) }
    def owner_display_name_configuration_needs_profile?
      owner_user_name_display_configuration_value == Configurable::UserNameDisplayConfiguration::NAME_AND_HANDLE
    end
  end
end
