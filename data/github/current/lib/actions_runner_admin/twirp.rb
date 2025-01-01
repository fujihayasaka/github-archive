# typed: true
# frozen_string_literal: true

module ActionsRunnerAdmin
  module Twirp
    autoload :BaseClient, "actions_runner_admin/twirp/base_client"
    autoload :RunnerAdminClient, "actions_runner_admin/twirp/runner_admin_client"
    autoload :NullClient, "actions_runner_admin/twirp/null_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < Error; end
  end
end
