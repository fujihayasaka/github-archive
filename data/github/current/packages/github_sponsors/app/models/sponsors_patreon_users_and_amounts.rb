# typed: true
# frozen_string_literal: true

class SponsorsPatreonUsersAndAmounts < T::Struct
  prop :amount_in_cents_by_patreon_user_id, T::Hash[String, Integer]

  # Public: The cursor to use to fetch the next page of results after this result set, if such a page exists.
  prop :next_cursor, T.nilable(String)
end
