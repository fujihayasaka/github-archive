# typed: true
# frozen_string_literal: true
require "authzd-client"

module Permissions
  module Authorizer

    # returns an Authzd::Response
    def self.authorize(request, options = {})
      ::Authzd.client.authorize(request)
    end

    # returns an Authzd::BatchResponse
    def self.batch_authorize(batch_request, options = {})
      ::Authzd.client.batch_authorize(batch_request)
    end
  end
end
