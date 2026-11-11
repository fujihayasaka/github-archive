# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class ConditionExpression < ApplicationRecord::Domain::Copilot
    self.table_name = "copilot_condition_expressions"

    sig { returns(String) }
    def self.condition_class_name
      "Copilot::Settings::ConditionExpression"
    end

    after_commit(on: [:update, :destroy, :create]) do
      CopilotDomain.domain.settings.clear_provider_cache(CopilotSettingsDbProvider::NAME)
    end

    include SettingsCore::ConditionExpressionBase
  end
end
