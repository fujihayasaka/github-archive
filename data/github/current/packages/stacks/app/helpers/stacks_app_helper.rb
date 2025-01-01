# typed: true
# frozen_string_literal: true

# TODO - Currently we do not have a way to get app status, hence this logic
# Once there is a generic way to get app status, we can remove this helper

require "httparty"

class StacksAppHelper
  HTTP_ERRORS = [
    HTTParty::Error, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
    Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
  ]

  def self.app_status_endpoint_exists?(app)
    return false unless app.present?
    return false unless app["url"].present?
    begin
      setup_status_url = URI("#{app['url']}/api/")
      response = HTTParty.get(setup_status_url)
      return response.code >= 200 && response.code < 300
    rescue *HTTP_ERRORS, StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub::Logger.log(fn: __method__, message: "Error checking app_status_endpoint_exists: #{e.message}", error: e)
    end
    false
  end

  def self.app_setup_completed?(repo, app)
    return false unless repo.present?
    return false unless app.present?
    return false unless app["integration"].present?
    return false unless app["installation"].present?
    begin
      setup_status_url = URI("#{app["integration"]['url']}/api/#{app["installation"]["id"]}/#{repo.name_with_owner}/status")
      response = HTTParty.get(setup_status_url)
      return response.code == 200
    rescue *HTTP_ERRORS, StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub::Logger.log(fn: __method__, message: "Error checking app_setup_completed: #{e.message}", error: e)
    end
    false
  end
end
