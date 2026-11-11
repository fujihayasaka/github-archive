# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingDetailComponent < ApplicationComponent
  # Renders a single row in the Copilot settings table. Two modes are supported so
  # policy rows and non-policy rows can share one component:
  # - Policy mode: pass `policy_class` + `copilot_entity`; the name, value, and
  #   label colour are derived from the Copilot policy.
  # - Static mode: pass `name` + `value` (and optional `label_scheme`) to render
  #   a non-policy row that matches the policy rows' markup.
  sig do
    params(
      policy_class: T.nilable(Copilot::PolicyInterface),
      copilot_entity: T.nilable(Copilot::Types::CopilotEntity),
      name: T.nilable(String),
      value: T.nilable(String),
      label_scheme: T.nilable(Symbol),
    ).void
  end
  def initialize(policy_class: nil, copilot_entity: nil, name: nil, value: nil, label_scheme: nil)
    @policy_class = policy_class
    @copilot_entity = copilot_entity
    @static_name = name
    @static_value = value
    @static_label_scheme = label_scheme
    @invert_badge_scheme = T.let(policy_class == Copilot::Policies::Snippy, T::Boolean)
  end

  sig { returns(String) }
  def policy_name
    policy = @policy_class
    return @static_name.to_s if policy.nil?

    policy.display_name
  end

  sig { returns(String) }
  def policy_id
    policy = @policy_class
    return policy_name.parameterize if policy.nil?

    policy.config_name
  end

  sig { returns(String) }
  memoize def policy_value
    policy = @policy_class
    entity = @copilot_entity
    return @static_value.to_s unless policy && entity

    if entity.sorbet_class == ::User
      policy.effective_value(T.cast(entity, Copilot::User))
    else
      policy.value(entity)
    end
  end

  sig { returns(String) }
  def policy_ui_value
    policy = @policy_class
    entity = @copilot_entity
    return @static_value.to_s unless policy && entity

    # show unconfigured as falling back to disabled for users
    if policy_value == policy.config_values[:unconfigured] && entity.sorbet_class == ::User
      "Unconfigured (disabled)"
    elsif policy_id == Copilot::Policies::CodingAgent.config_name && policy_value == policy.config_values[:no_policy]
      "Defined by organization"
    elsif policy_id == Copilot::Policies::CodingAgent.config_name && policy_value == Copilot::Policies::CodingAgent::ENTERPRISE_MANAGEMENT_VALUE
      "Enable for selected organizations"
    else
      policy_value.titleize
    end
  end

  sig { returns(Symbol) }
  def label_scheme
    policy = @policy_class
    entity = @copilot_entity
    return @static_label_scheme || :default unless policy && entity

    case policy_value
    when policy.config_values[:enabled]
      @invert_badge_scheme ? :danger : :success
    when policy.config_values[:disabled]
      @invert_badge_scheme ? :success : :danger
    when policy.config_values[:no_policy]
      :secondary
    when policy.config_values[:unconfigured]
      if entity.sorbet_class == ::User
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
