# typed: true
# frozen_string_literal: true

module ActionsRunService
  module Twirp
    autoload :BaseClient, "actions_run_service/twirp/base_client"
    autoload :RunServiceClient, "actions_run_service/twirp/run_service_client"
    autoload :RunServiceLabClient, "actions_run_service/twirp/run_service_lab_client"
    autoload :NullClient, "actions_run_service/twirp/null_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < Error; end
  end
end
