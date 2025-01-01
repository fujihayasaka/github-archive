# typed: true
# frozen_string_literal: true

# no associated template
# tests are covered by the implementing class

# rubocop:disable ViewComponent/ComponentsHaveUnitTests
module Businesses::Policies::SecurityAnalysis::BasePolicy
  include FeatureFlagHelper

  extend T::Sig
  extend T::Helpers

  abstract!

  sig { abstract.returns(String) }
  def policy_name; end

  PolicyItem = Struct.new(:label, :description, :active, :value)

  sig { abstract.returns(T::Array[PolicyItem]) }
  def policy_options; end

  sig { returns(String) }
  def selected_policy_text
    T.must(policy_options.find(&:active)).label
  end

  protected

  sig { returns(T::Boolean) }
  def use_action_menu_component?
    feature_enabled_globally_or_for_user?(feature_name: :codescanning_ghas_policy_action_menu)
  end
end
