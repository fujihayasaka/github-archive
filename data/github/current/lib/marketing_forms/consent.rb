# typed: strict
# frozen_string_literal: true

module MarketingForms
  class Consent < T::Enum
    enums do
      Implicit = new("optInImplicit")
      Explicit = new("optInExplicit")
    end

    sig { returns(String) }
    def to_s
      serialize.to_s
    end
  end
end
