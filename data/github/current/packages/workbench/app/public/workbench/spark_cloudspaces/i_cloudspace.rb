# typed: strict
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    module ICloudspace
      extend T::Helpers

      abstract!

      sig { abstract.returns(CloudEnvironments::ICloudEnvironment) }
      def cloud_environment; end

      delegate :provisioned?, to: :cloud_environment
    end
  end
end
