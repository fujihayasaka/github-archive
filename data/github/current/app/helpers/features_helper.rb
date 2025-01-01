# typed: true
# frozen_string_literal: true

module FeaturesHelper
  # Helper to display pre-release badge on early-access features
  #
  # Options:
  #   feature_flag - The symbolized feature flag this is badging
  #   public_name - The name to use in the view tooltip. If not provided feature flag
  #     will automatically be used
  #   internal_feedback_url - Full URL for users to provide feedback on the feature
  #   external_feedback_url - Full URL for staff to provide feedback on the feature
  #   additional_classes - string of additional CSS classes to add to the badge
  #
  # Returns the rendered badge (which must be outputted with <%='s)
  def prerelease_badge(feature_flag, public_name: nil, external_feedback_url: nil, internal_feedback_url: nil, additional_classes: nil)
    T.bind(self, T.untyped)
    name = public_name ? public_name : feature_flag
    render "prerelease/badge", view: create_view_model(
      Prerelease::BadgeView,
      feature_flag: feature_flag,
      public_name: name.to_s.humanize(capitalize: false),
      external_feedback_url: external_feedback_url,
      internal_feedback_url: internal_feedback_url,
      additional_classes: additional_classes,
      current_repository: current_repository,
    )
  end
end
