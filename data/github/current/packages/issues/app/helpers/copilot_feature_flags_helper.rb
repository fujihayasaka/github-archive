# typed: strict
# frozen_string_literal: true

module CopilotFeatureFlagsHelper
  sig { params(actor: T.nilable(User), organization: T.nilable(Organization)).returns(T::Boolean) }
  def self.issue_cca_visualization_enabled?(actor, organization: nil)
    return false if actor.nil?

    enabled = FeatureFlag.vexi.enabled?(:issue_cca_visualization, actor, organization, default: false)

    enabled
  end
end
