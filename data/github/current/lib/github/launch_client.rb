# typed: true
# frozen_string_literal: true

require "github-launch"

module GitHub
  module LaunchClient
    autoload :Deployer, "github/launch_client/deployer"
    autoload :RunnerGroupResponse, "github/launch_client/runner_group_response"
    autoload :TracingInterceptor, "github/launch_client/tracing_interceptor"
    autoload :TenantInterceptor, "github/launch_client/tenant_interceptor"

    Error = Class.new(RuntimeError)
    ServiceUnavailable = Class.new(Error)
  end
end
