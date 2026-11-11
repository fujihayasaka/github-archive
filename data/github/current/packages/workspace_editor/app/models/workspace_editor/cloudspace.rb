# typed: true
# frozen_string_literal: true

module WorkspaceEditor
  class Cloudspace
    extend T::Helpers
    include Cloudspaces::ICloudspace

    COPILOT_WORKSPACE_ID = "hadron"
    sig { override.returns(CloudEnvironments::ICloudEnvironment) }
    attr_reader :cloud_environment

    sig { params(cloud_environment: CloudEnvironments::ICloudEnvironment).void }
    def initialize(cloud_environment)
      @cloud_environment = cloud_environment
    end
  end
end
