# typed: strict
# frozen_string_literal: true

class SponsorsAgreement::Signatures::ExportOption < T::Enum
  enums do
    All = new("all")
    SignedInLastWeek = new("signed_in_last_week")
    ExpiresInNextWeek = new("expires_in_next_week")
  end

  sig { returns(String) }
  def description
    case self
    when All
      "All signatures"
    when SignedInLastWeek
      "Signed in the last 7 days"
    when ExpiresInNextWeek
      "Expiring in the next 7 days"
    else
      T.absurd(self)
    end
  end
end
