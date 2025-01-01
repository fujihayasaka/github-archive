# typed: strict
# frozen_string_literal: true

module CloudEnvironments
  module ICreateResult
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.returns(ICloudEnvironment) }
    def cloud_environment; end

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
