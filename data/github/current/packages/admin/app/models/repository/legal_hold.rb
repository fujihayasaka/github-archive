# typed: true
# frozen_string_literal: true

module Repository::LegalHold
  # Does this repository have a legal hold placed on that should prevent it from
  # being removed entirely?
  #
  # Returns boolean.
  def legal_hold?
    # It's always possible that our owner has been wiped out. Just in case that
    # hold still managed to exist we'll provide an extra-safe method of
    # checking.
    ::LegalHold.find_by(user_id: T.unsafe(self).owner_id).present?
  end
end
