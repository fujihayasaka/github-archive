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
    (logged_in? || GitHub.flipper[:anonymous_search_and_codeview].enabled?) && GitHub.flipper[:react_code_search_enabled].enabled?
  end
end
