# typed: true
# frozen_string_literal: true

module Configurable
  module EnableProjectsAutomation
    KEY = "projects_automation.enable".freeze

    def projects_automation_enabled?
      T.bind(self, T.class_of(GitHub))
      # default to true for non github enterprise
      return true unless GitHub.enterprise?

      config.enabled?(KEY)
    end

    # Enable projects automation at the enterprise level by creating a Configurable value of `true`
    # for Configurable::EnableProjectsAutomation::KEY
    #
    # actor: The user making the change
    #
    # returns: nil
    sig { params(actor: User).void }
    def enable_projects_automation(actor:)
      T.bind(self, T.class_of(GitHub))

      config.enable!(KEY, actor)
    end

    # Disables projects automation at the enterprise level by enabling a Configurable value of `false`
    # for Configurable::EnableProjectsAutomation::KEY
    #
    # actor: the user making the change
    #
    # returns nil
    sig { params(actor: User).void }
    def disable_projects_automation(actor:)
      T.bind(self, T.class_of(GitHub))

      config.disable!(KEY, actor)
    end

    # Clears the setting of the projects automation policy by removing the value entirely
    # for Configurable::EnableProjectsAutomation::KEY
    #
    # actor: the user making the change
    #
    # returns: nil
    sig { params(actor: User).void }
    def clear_projects_automation_setting(actor:)
      T.bind(self, T.class_of(GitHub))

      config.delete(KEY, actor)
    end
  end
end
