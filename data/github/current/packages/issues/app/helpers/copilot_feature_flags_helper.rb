# typed: strict
# frozen_string_literal: true

module CopilotFeatureFlagsHelper

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def self.decoupled_mode_enabled?(actor)
    return false if actor.nil?

    FeatureFlag.vexi.enabled?(:copilot_mission_control_decoupled_mode, actor, default: false) &&
      FeatureFlag.vexi.enabled?(:issue_cca_visualization_decoupled_mode, actor, default: false)
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def self.issue_cca_visualization_enabled?(actor)
    return false if actor.nil?

    FeatureFlag.vexi.enabled?(:issue_cca_visualization, actor, default: false) || decoupled_mode_enabled?(actor)
  end
end
