# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveConnectKeyValues < MoveKeyValuesBase
      class ConnectKeyValues < ApplicationRecord::Domain::Users
        self.table_name = :connect_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        ConnectKeyValues
      end

      iterate_key_values [
        "ghe-install-token-%",
        "ghe-install-id-%",
        "connect-failed-metrics",
        "enterprise\\_installation:usage\\_metrics:%",
        "ghe-install-iss",
        "ghe-install-id",
        "ghe-install-version",
        "ghe-install-key",
        "ghe-install-owner-type",
        "ghe-install-owner-identifier",
        "ghe-install-server-id",
        "ghe-install-requested-features",
        "ghe-install-token",
        "ghe-install-client-secret",
        "ghe-install-temp-token",
        "ghe-install-upload-id",
        "enterprise-installation-deny-%",
        "enterprise-installation-user-login-app-%.%",
        "ghe-install-organization-login",
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveConnectKeyValues.new(args).run
end
