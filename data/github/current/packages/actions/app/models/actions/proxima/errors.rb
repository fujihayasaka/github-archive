# typed: true
# frozen_string_literal: true

module Actions::Proxima
  module Errors
    class HTTPResponseError < StandardError
      def initialize(msg = "", url:, status:, body: nil, errors: nil)
        super(msg)
        @url = url
        @status = status
        @body = body
        @errors = errors
      end

      attr_reader :url, :status, :body, :errors
    end

    class WorkflowTemplatesError < HTTPResponseError; end
    class ActionsVerifiedOwnersError < HTTPResponseError; end
  end
end
