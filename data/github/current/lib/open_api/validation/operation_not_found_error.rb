# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class OperationNotFoundError < OpenApi::Validation::Error
      code :operation_not_found

      attr_reader :request_path, :request_method, :matched_path, :method

      def initialize(request_method, request_path, matched_path, method)
        @request_path = request_path
        @request_method = request_method
        @matched_path = matched_path
        @method = method
      end

      def public_message
        "Not Found"
      end

      def developer_message
        description_file = "api.github.com.yaml"
        if GitHub.enterprise?
          description_file = "ghes-x.xx.yaml"
        end

        <<~MD
        "Routing error for `#{request_method} #{request_path}`: Path was found (#{matched_path}) but no operation could be found for method #{method.upcase}."

        Please consult app/api/description/#{description_file} to ensure that you are utilizing the correct endpoint correctly.

        If your endpoint is new, you can add the endpoint by consulting the documentation [here](https://thehub.github.com/engineering/development-and-ops/public-apis/contributing-to-openapi/).

        If your endpoint is deprecated, internal, or unreleased you can either add the endpoint (see above) or add it to the ignore list [here](https://github.com/github/github/blob/master/lib/open_api/validation/ignore_list.rb).

        If you need assistance, please visit the #api-platform channel.
        MD
      end
    end
  end
end
