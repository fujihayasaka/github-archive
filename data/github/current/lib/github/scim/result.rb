# typed: true
# frozen_string_literal: true

# Result class that is returned from all methods calls it is checked in the
# process_scim_result method and appropriate status and result is returned
module GitHub
  module SCIM
    class Result
      # readers for result properties
      attr_reader :status_code,
        :error_msg,
        :detail,
        :scim_type,
        :serialize_method,
        :results,
        :excluded_attributes

      # initialization of a result only status_code is needed
      # Please utilize provided static initializers
      def initialize(status_code:, error_msg: nil, detail: nil, scim_type: nil,
        serialize_method: nil, results: nil, excluded_attributes: nil)
        @status_code = status_code
        @error_msg = error_msg
        @detail = detail
        @scim_type = scim_type
        @serialize_method = serialize_method
        @results = results
        @excluded_attributes = excluded_attributes
      end

      # Public: Shortcut method to deliver a result with an error message
      #
      # status_code - a status code to be returned (200, 201, 404, etc.)
      # error_msg   - an error message associated with the status
      #
      # Returns initiated Result objet
      def self.deliver_error(status_code, error_msg)
        new(status_code: status_code, error_msg: error_msg)
      end

      # Public: Shortcut method to deliver a result with a scim type and/or detail message
      #
      # status_code - a status code to be returned (200, 201, 404, etc.)
      # scim_type   - a specific type of an error as defined in scim requirements
      # detail      - an error message associated with the status
      #
      # Returns initiated Result objet
      def self.deliver_scim_error(status_code, scim_type: nil, detail: nil)
        new(status_code: status_code, detail: detail, scim_type: scim_type)
      end

      # Public: Shortcut method to deliver a scim result, with specific status code and serialization
      #
      # serialize_method - method used to serialize a result object
      # result           - result to serialize
      # status_code - a status code to be returned (200, 201, 404, etc.)
      #
      # Returns initiated Result objet
      def self.deliver_scim(serialize_method, results, status_code, excluded_attributes: nil)
        new(status_code: status_code, serialize_method: serialize_method, results: results,
          excluded_attributes: excluded_attributes)
      end

      # Public: Check if result contains a successful return
      #
      # Returns true when result contains a successful return, otherwise false
      def success?
        status_code <= 300
      end

      private_class_method :new
    end
  end
end
