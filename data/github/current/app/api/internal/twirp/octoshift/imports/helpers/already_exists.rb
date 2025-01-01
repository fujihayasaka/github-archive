# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module AlreadyExists
        include Kernel

        # @param attributes [Hash] The attributes to check for existence. If this contains a joins: key, it will make
        # those joins available to the query.
        def check_for_existing_record!(model_type, attributes)
          joins = attributes[:joins] || []
          attributes.delete(:joins)

          return unless records_exist?(model_type, attributes, joins)

          matching_existing_records = existing_records(model_type, attributes, joins)
          existing_record_id = matching_existing_records.last.id

          raise Api::Internal::Twirp::Octoshift::Errors::AlreadyExists.new(
            model_type,
            existing_record_id
          )
        end

        def records_exist?(model_type, attributes, joins)
          Replica.new(model_type).query do |model|
            if !joins.empty?
              model = model.joins(*joins)
            end
            model.where(**attributes).exists?
          end
        end

        def existing_records(model_type, attributes, joins)
          Replica.new(model_type).query do |model|
            if !joins.empty?
              model = model.joins(*joins)
            end
            model.where(**attributes)
          end
        end
      end
    end
  end
end
