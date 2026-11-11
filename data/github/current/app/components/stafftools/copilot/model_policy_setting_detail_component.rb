# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::ModelPolicySettingDetailComponent < ApplicationComponent
  sig { params(model: Copilot::ModelsRegistryCache, copilot_entity: Copilot::Types::CopilotEntity).void }
  def initialize(model:, copilot_entity:)
    @model = model
    @copilot_entity = copilot_entity
  end

  private

  sig { returns(String) }
  memoize def current_value
    @copilot_entity.model_policy(@model.model_key)
  end

  sig { returns(T::Boolean) }
  memoize def is_user?
    @copilot_entity.configurable_object.is_a?(::User)
  end

  sig { returns(String) }
  def policy_ui_value
    if is_user? && (@copilot_entity.copilot_plan_business? || @copilot_entity.copilot_plan_enterprise?)
      # Sorbet doesn't understand the type narrowing above
      case @copilot_entity
      when Copilot::User
        enterprise_policy_set = @copilot_entity.copilot_businesses.any? do |b|
          b.model_enabled?(@model.model_key) || b.model_disabled?(@model.model_key)
        end
        org_policy_set = @copilot_entity.copilot_organizations.any? do |o|
          o.model_enabled?(@model.model_key) || o.model_disabled?(@model.model_key)
        end

        return "Unconfigured (disabled)" unless enterprise_policy_set || org_policy_set
      end
    end

    current_value.titleize
  end

  sig { returns(Symbol) }
  def label_scheme
    case current_value
    when "enabled" then :success
    when "disabled" then :danger
    when "no_policy" then :secondary
    when "unconfigured" then is_user? ? :danger : :default # unconfigured defaults to disabled for users
    else :default
    end
  end
end
