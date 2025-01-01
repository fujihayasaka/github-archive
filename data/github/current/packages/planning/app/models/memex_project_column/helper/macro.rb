# typed: strict
# frozen_string_literal: true

# This module provides helper methods for resolving search query macros (e.g. "@me").
module MemexProjectColumn::Helper::Macro
  extend T::Helpers
  requires_ancestor { MemexProjectColumn::Field::Base }

  # Resolve the "@me" macro if possible, otherwise return the given value unchanged.
  #
  # For anonymous users, this will return the literal "@me" string, which is not a valid login.
  # That fact can be exploited to return empty results (as we should for an anonymous request)
  # that uses "@me").
  #
  # @param value The string that is potentially the literal "@me".
  # @param context The context in which the query is being executed.
  sig { params(value: String, context: Search::Memex::Context).returns(String) }
  private def resolve_me_macro(value:, context:)
    if value == Search::Query::MACRO_ME && context.viewer.present?
      T.must(context.viewer).display_login
    else
      value
    end
  end
end
