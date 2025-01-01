# typed: strict
# frozen_string_literal: true

# See https://thehub.github.com/engineering/development-and-ops/dotcom/feature-flags/overview/
module OauthApplication::FeatureFlagMethods
  extend T::Helpers

  requires_ancestor { OauthApplication }

  # Does this OAuth Application belong to the "github" org or to a GitHub
  # staff member?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def preview_features?
    return false unless GitHub.preview_features_enabled?
    github_owned?
  end

  # Is codesearch disabled for the current OAuth Application? This feature
  # flag is used to block applications that are negatively impacting the
  # Elasticsearch cluster.
  #
  # see https://devportal.githubapp.com/feature-flags/disable_codesearch/overview
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def codesearch_disabled?
    self.feature_enabled?(:disable_codesearch)
  end
end
