# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingsComponent < ApplicationComponent
  include GitHub::Memoizer

  renders_many :prepended_rows

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
    case @configurable
    when Copilot::User
      Copilot::ModelsRegistryCache.for_user(@configurable)
    when Copilot::Organization
      Copilot::ModelsRegistryCache.for_organization(@configurable)
    when Copilot::Business
      Copilot::ModelsRegistryCache.for_enterprise(@configurable)
    end
  end
end
