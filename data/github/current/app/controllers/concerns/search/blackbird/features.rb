# typed: strict
# frozen_string_literal: true

module Search::Blackbird::Features
  extend T::Helpers

  include GitHub::Memoizer

  abstract!

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  # Returns true if blackbird code search is enabled.
  sig { returns(T::Boolean) }
  memoize def blackbird_enabled?
    (logged_in? || FeatureFlag.vexi.enabled?(:anonymous_search_and_codeview, default: false)) && FeatureFlag.vexi.enabled?(:react_code_search_enabled, default: false)
  end
end
