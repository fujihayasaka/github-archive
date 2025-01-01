# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  module IFindOrCreateResult
    extend T::Sig
    extend T::Helpers
    include Kernel

    interface!

    sig { abstract.returns(T.nilable(IHadronCloudspace)) }
    def hadron_cloudspace; end

    sig { abstract.returns(T.nilable(Codespaces::Environment)) }
    def env; end

    sig { abstract.returns(T::Boolean) }
    def found?; end
  end
end
