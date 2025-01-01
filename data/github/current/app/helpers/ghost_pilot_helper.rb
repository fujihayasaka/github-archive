# typed: true
# frozen_string_literal: true

module GhostPilotHelper
  extend T::Helpers
  include GitHub::Memoizer
  include GitHub::ResilienceMixin

  abstract!

  sig { abstract.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
  def current_copilot_user_v2; end

  sig { abstract.params(feature_name: T.nilable(Symbol)).returns(T::Boolean) }
  def user_feature_enabled?(feature_name); end

  # Is ghost pilot available in the context described by "current_copilot_user"
  #
  # The user must have been assigned a Copilot for Enterprise seat by an organization or business that has enabled
  # beta features for Copilot, and must remain personally opted-in (default) for the feature.
  sig { returns(T::Boolean) }
  memoize def ghost_pilot_available?
    # Ensure the user is part of the feature flag in general (whether they
    # opted-out is checked elsewhere)
    with_database_error_fallback(fallback: false) do
      return false unless user_feature_enabled?(:ghost_pilot_pr_autocomplete)
      !!current_copilot_user_v2&.beta_features_github_chat_enabled?
    end
  end
end
