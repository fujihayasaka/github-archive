# typed: strict
# frozen_string_literal: true

class ProgrammaticAccessTokenType < T::Enum
  extend T::Sig

  enums do
    FineGrained = new("fine_grained")
    Classic = new("classic")
  end

  sig { returns(String) }
  def name
    case self
    when FineGrained
      "fine-grained personal access tokens"
    when Classic
      "personal access tokens (classic)"
    else
      T.absurd(self)
    end
  end
end
