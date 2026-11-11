# frozen_string_literal: true

require "octokit"

module Octokit
  # Raised when GitHub returns a 410 HTTP status code
  class Gone < ClientError; end
end

module Dependabot
  module OctokitMiddleware
    class RaiseGoneError < Faraday::Middleware
      def on_complete(response)
        status = response[:status].to_i
        return unless status == 410

        raise Octokit::Gone, response
      end
    end
  end
end
