# typed: true
# frozen_string_literal: true

# Top level namespace for the authorization service
#
# The authorization service provides operations for:
#   * Answering questions such us:
#      - Can an actor access a certain resouce?
#      - What are the resources an actor has access to?
#   * Run commands like:
#      - Grant access to an actor for accessing a resource.
#
# Both commands and queries in the authorization service return collections
module Authorization
  autoload :Errors,         "authorization/errors"
  autoload :Helpers,        "authorization/helpers"
  autoload :Operation,      "authorization/operation"
  autoload :AsyncOperation, "authorization/async_operation"
  autoload :BaseResult,     "authorization/base_result"
  autoload :Result,         "authorization/result"
  autoload :AsyncResult,    "authorization/async_result"

  def self.service=(service)
    @service = service
  end

  def self.service
    @service ||= Service.new
  end
end

require "authorization/service"
