# frozen_string_literal: true
# typed: strict

module Vexi
    # Public: Vexi entity interface.
  module Entity
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns String }
    def name; end
  end
end
