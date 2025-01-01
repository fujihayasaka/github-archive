# typed: true
# frozen_string_literal: true

module Workbench
  class Cloudspace
    extend T::Helpers
    include Workbench::SparkCloudspaces::ICloudspace

    COPILOT_WORKBENCH_ID = "workbench"
    sig { override.returns(CloudEnvironments::ICloudEnvironment) }
    attr_reader :cloud_environment

    sig { params(cloud_environment: CloudEnvironments::ICloudEnvironment).void }
    def initialize(cloud_environment)
      @cloud_environment = cloud_environment
    end
  end
end
