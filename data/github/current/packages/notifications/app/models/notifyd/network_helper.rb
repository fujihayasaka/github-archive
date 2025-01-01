# typed: true
# frozen_string_literal: true

module Notifyd
  module NetworkHelper
    include GitHub::Tracing
    extend T::Helpers
    requires_ancestor { Kernel }

    NOTIFYD_REQUEST_STAT = "notifications.notifyd_request"

    # Include this module in any new error class so it can be rescued with:
    #
    #   class MyError < StandardError
    #     include APIError
    #   end
    #
    #   begin
    #     raise MyError, "Oh, no!"
    #   rescue Notifyd::NetworkHelper::APIError => e
    #     # rescue block for MyError
    #   end
    module APIError
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.returns(String) }
      def message; end
    end

    class ResponseError < StandardError
      include APIError

      def initialize(request_class, response_error)
        @request_class = request_class
        @code = response_error.code
        @msg = response_error.msg
      end

      def message
        "Error response when calling the #{@request_class} RPC on notifyd. Code: #{@code}. Message: #{@msg}"
      end
    end

    # ConnectionError can be rescued inside any Resiliency::Response instance
    class ConnectionError < Resiliency::Response::UnavailableError
      include APIError

      def request_class=(request_class)
        @message = "Failed when connecting to notifyd for the #{request_class} RPC"
      end

      def message
        @message || "Failed when connecting to notifyd for RPC"
      end
    end

    class ResponseHandler
      attr_reader :request_class_name, :raise_error, :tags

      def initialize(request_class_name:, raise_error:, tags:)
        @request_class_name = request_class_name
        @raise_error = raise_error
        @tags = tags
      end

      def execute
        response = yield
        return handle_success(response: response) if response.error.nil?
        return handle_connection_error(error_tag: "error:#{response.error.code}") if response.error&.code == :unavailable
        handle_error(response: response, error_tag: "error:#{response.error.code}")
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        handle_connection_error(error_tag: "error:connection")
      end

      private

      def request_tag
        request_class_name.split("::").last
      end

      def handle_success(response:)
        GitHub.dogstats.increment(
          NOTIFYD_REQUEST_STAT,
          tags: [
            "request:#{request_tag}",
            "success:true",
          ] + tags
        )
        # add logging here
        response
      end

      def handle_error(response:, error_tag:)
        err = ResponseError.new(request_class_name, response.error)
        NotifydFailbot.report(err)
        GitHub.dogstats.increment(
          NOTIFYD_REQUEST_STAT,
          tags: [
            "request:#{request_tag}",
            "success:false",
            error_tag,
          ] + tags
        )
        raise err if raise_error
        nil
      end

      def handle_connection_error(error_tag:)
        err = ConnectionError.new
        err.request_class = request_class_name
        GitHub.dogstats.increment(
          NOTIFYD_REQUEST_STAT,
          tags: [
            "request:#{request_tag}",
            "success:false",
            error_tag,
          ] + tags
        )
        raise err if raise_error
        nil
      end

    end

    def make_network_request_to_notifyd(request_class_name, raise_error = false, tags = [], &block)
      GitHub.tracer.in_span("notifyd.network_helper", kind: :internal, attributes: { "code.namespace" => request_class_name.to_s }) do
        ResponseHandler.new(request_class_name: request_class_name, raise_error: raise_error, tags: tags).execute do
          block.call
        end
      end
    end
  end
end
