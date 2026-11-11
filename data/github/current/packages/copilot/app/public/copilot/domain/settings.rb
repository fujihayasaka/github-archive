# typed: strict
# frozen_string_literal: true

module Copilot
  class Domain
    class Settings < GH::Domain::Base
      include SettingsCore::DomainAccessorBase

      register_group Copilot::Settings::CopilotModelsGroup.new

      # TODO: The GH::Decorator::WrapPreloads decorator breaks if the AR one comes first. This should be fixed
      # before launch.
      register_provider Copilot::Settings::CopilotModelsSettingProvider.new
      register_provider Copilot::Settings::CopilotSettingsDbProvider.new
    end
  end
end
