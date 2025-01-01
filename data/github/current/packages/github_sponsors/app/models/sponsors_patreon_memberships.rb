# typed: true
# frozen_string_literal: true

class SponsorsPatreonMemberships < T::Struct
  # Public: Patreon API response
  prop :memberships, T::Array[T::Hash[String, T.untyped]]

  # Public: The cursor to use to fetch the next page of results after this result set, if such a page exists.
  prop :next_cursor, T.nilable(String)
end
