# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  module ICreateResult
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(T.nilable(IHadronCloudspace)) }
    def hadron_cloudspace; end

    sig { abstract.returns(T.nilable(Codespaces::Environment)) }
    def env; end

    sig { abstract.returns(T.nilable(String)) }
    def github_token; end

    sig { abstract.returns(T.nilable(Float)) }
    def github_token_valid_after; end

    sig { abstract.returns(T::Boolean) }
    def provisioned?; end
  end
end
