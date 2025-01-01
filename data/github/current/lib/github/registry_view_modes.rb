# typed: true
# frozen_string_literal: true

module GitHub
  class RegistryViewModes

    ENABLED = "enabled"
    DISABLED = "disabled"
    READ_ONLY = "readonly"

    def self.registry_view_warning_msg(registry_name, mode)
      return if mode == ENABLED

      if mode == DISABLED
        "You cannot publish or install this package because the #{registry_name} registry is disabled. Please contact your Enterprise admins to enable it."
      elsif mode == READ_ONLY
        "#{registry_name} registry is in read-only mode and does not allow publishing of a new image. Please contact your Enterprise admins to enable it."
      end
    end

  end
end
