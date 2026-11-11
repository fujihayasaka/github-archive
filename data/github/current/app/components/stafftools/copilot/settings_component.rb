# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingsComponent < ApplicationComponent
  include GitHub::Memoizer

  renders_many :prepended_rows

  # Optional row rendered immediately above the AutomaticCodeReview policy row.
  # The org settings page uses it to show the Copilot code review ruleset state
  # directly above the per-user "Automatic Copilot code review" policy row.
  renders_one :automatic_code_review_ruleset_row

  sig { returns(Copilot::Types::CopilotEntity) }
  attr_reader :configurable

  sig { params(configurable: Copilot::Types::CopilotEntity).void }
  def initialize(configurable)
    @configurable = configurable
  end

  private

  sig { returns(T::Array[Copilot::PolicyInterface]) }
  memoize def policies
    Copilot::Policies::ALL.reject do |policy|
      if @configurable.is_a?(Copilot::User) && policy == Copilot::Policies::DashboardEntryPoint && !@configurable.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false)
        true
      else
        !policy.available_for?(@configurable)
      end
    end
  end

  sig { returns(T::Array[Copilot::ModelsRegistryCache]) }
  memoize def model_registry_models
    @configurable.registry_models
  end
end
