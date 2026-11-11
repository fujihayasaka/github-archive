# typed: strict
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    module ICloudspace
      extend T::Helpers

      abstract!

      sig { abstract.returns(CloudEnvironments::ICloudEnvironment) }
      def cloud_environment; end

      delegate :provisioned?, to: :cloud_environment
    end
  end
end
