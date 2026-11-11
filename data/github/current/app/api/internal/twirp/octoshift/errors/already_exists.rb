# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Errors
    class AlreadyExists < StandardError
      include Api::Internal::Twirp::Octoshift::Imports::Helpers::ErrorHandler

      attr_reader :model_type, :existing_record_id

      def initialize(model_type, existing_record_id)
        @model_type = model_type
        @existing_record_id = existing_record_id
      end

      def message
        "#{model_type} ##{existing_record_id} already exists"
      end

      def to_twirp_error
        already_exists_error_handler(
          model_type.to_s,
          existing_record_id
        )
      end
    end
  end
end
