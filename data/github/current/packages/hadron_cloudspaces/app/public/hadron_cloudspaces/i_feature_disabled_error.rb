# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  module IFeatureDisabledError
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(T.nilable(String)) }
    def message; end
  end
end
