# typed: true
# frozen_string_literal: true

class SponsorsAgreement::Signatures::SortOption < T::Enum
  enums do
    RecentlySigned = new("recently_signed")
    OldestSigned = new("oldest_signed")
    SoonestExpiration = new("soonest_expiration")
    FurthestExpiration = new("furthest_expiration")
  end

  sig { returns(T::Hash[Symbol, Symbol]) }
  def ordering_arguments
    case self
    when RecentlySigned
      { created_at: :desc }
    when OldestSigned
      { created_at: :asc }
    when SoonestExpiration
      { expires_on: :asc }
    when FurthestExpiration
      { expires_on: :desc }
    else
      T.absurd(self)
    end
  end
end
