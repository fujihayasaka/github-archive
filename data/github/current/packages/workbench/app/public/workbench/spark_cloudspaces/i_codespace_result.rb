# typed: strict
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    module ICodespaceResult
      extend T::Helpers
      include Kernel

      interface!

      sig { abstract.returns(ICloudspace) }
      def workbench_cloudspace; end

      sig { abstract.returns(T.nilable(Codespaces::Environment)) }
      def env; end

    end
  end
end
