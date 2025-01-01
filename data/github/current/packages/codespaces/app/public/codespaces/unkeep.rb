# typed: strict
# frozen_string_literal: true

module Codespaces
  class Unkeep < Command
    extend T::Sig

    sig { params(codespace: Codespace).void }
    def initialize(codespace)
      @codespace = codespace
    end

    sig { override.returns(T.nilable(Codespace)) }
    def perform
      @codespace.update!(keep: false, shutdown_at: Time.now)
    end
  end
end
