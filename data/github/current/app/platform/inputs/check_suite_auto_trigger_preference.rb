# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckSuiteAutoTriggerPreference < Platform::Inputs::Base
      description "The auto-trigger preferences that are available for check suites."

      argument :app_id, ID, "The node ID of the application that owns the check suite.", required: true
      argument :setting, Boolean, "Set to `true` to enable automatic creation of CheckSuite events upon pushes to the repository.", required: true
    end
  end
end
