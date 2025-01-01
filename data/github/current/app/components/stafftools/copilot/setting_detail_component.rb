# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingDetailComponent < ApplicationComponent
  sig do params(
    policy_class: Copilot::Policy,
    copilot_entity: Copilot::Types::CopilotEntity,
  ).void
  end
  def initialize(policy_class:, copilot_entity:)
    @policy_class = policy_class
    @copilot_entity = copilot_entity
    @invert_badge_scheme = T.let(policy_class == Copilot::Policies::Snippy, T::Boolean)
  end

  sig { returns(String) }
  def policy_name
    @policy_class.display_name
  end

  sig { returns(String) }
  def policy_id
    @policy_class.config_name
  end

  sig { returns(String) }
  memoize def policy_value
    if @copilot_entity.sorbet_class == ::User
      @policy_class.effective_value(T.cast(@copilot_entity, Copilot::User)) || @policy_class.config_values[:disabled]
    else
      @policy_class.value(@copilot_entity)
    end
  end

  sig { returns(String) }
  def policy_ui_value
    # show unconfigured as falling back to disabled for users
    if policy_value == @policy_class.config_values[:unconfigured] && @copilot_entity.sorbet_class == ::User
      "Unconfigured (disabled)"
    else
      policy_value.titleize
    end
  end

  sig { returns(Symbol) }
  def label_scheme
    case policy_value
    when @policy_class.config_values[:enabled]
      @invert_badge_scheme ? :danger : :success
    when @policy_class.config_values[:disabled]
      @invert_badge_scheme ? :success : :danger
    when @policy_class.config_values[:no_policy]
      :secondary
    when @policy_class.config_values[:unconfigured]
      if @copilot_entity.sorbet_class == ::User
        # unconfigured defaults to disabled for users so make it red in that case
        :danger
      else
        :default
      end
    else
      :default
    end
  end
end
