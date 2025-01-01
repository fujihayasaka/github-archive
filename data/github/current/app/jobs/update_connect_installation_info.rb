# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateConnectInstallationInfo < ApplicationJob
  queue_as :github_connect

  schedule interval: 1.week, condition: -> { GitHub.dotcom_connection_enabled? }

  def perform
    token = dotcom_connection.authentication_token
    return if token.nil?
    github_connect_authenticator.update_installation_info(token)
  end

  def dotcom_connection
    @dotcom_connection ||= ::DotcomConnection.new
  end

  def github_connect_authenticator
    @github_connect_authenticator ||= dotcom_connection.authenticator_with_license
  end
end
