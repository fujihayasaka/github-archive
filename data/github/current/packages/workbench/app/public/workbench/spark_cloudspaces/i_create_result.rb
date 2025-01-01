# typed: strict
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    module ICreateResult
      extend T::Helpers

      interface!

      sig { abstract.returns(ICloudspace) }
      def workbench_cloudspace; end

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
end
