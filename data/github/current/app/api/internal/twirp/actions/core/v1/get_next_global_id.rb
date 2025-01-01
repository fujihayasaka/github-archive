# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetNextGlobalId
        NO_OBJECT_FOUND_MESSAGE = "No object found for global_id"
        NO_TYPE_FOUND_MESSAGE = "No type found for global_id"
        UNPARSABLE_MESSAGE = "Unparsable global_id"
        INTERNAL_ERROR = "Error retrieving next_global_id"
        NEXT_ID_DOES_NOT_EXIST_MESSAGE = "Next global id does not exist"

        attr_reader :req

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          @req = request
        end

        # Returns next global id for an existing global id
        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "global_id") if req.global_id.blank?

          global_id = req.global_id

          if Platform::Helpers::GlobalId.next?(global_id)
            # If the global_id is already a next global id, we can just return it
            GitHub.dogstats.increment(
              "actions.twirp.get_next_global_id",
              tags: ["conversion_status:unnecessary",]
            )
            return next_global_id_response(global_id)
          end

          begin
            parsed = Platform::Helpers::GlobalId.parse(req.global_id)
          rescue Platform::Errors::NotFound
            return error_response(UNPARSABLE_MESSAGE, nil)
          end

          if Platform::Helpers::GlobalId::TOP_LEVEL_TYPES.include?(parsed.type)
            # If the global_id is top level type, we can just build the next global id without an object lookup
            next_global_id = Platform::Helpers::GlobalId.build_next_global_id(parsed.type, parsed.id.to_i)
            GitHub.dogstats.increment(
              "actions.twirp.get_next_global_id",
              tags: ["conversion_status:success", "type:#{parsed.type}"]
            )
            return next_global_id_response(next_global_id)
          end

          unless type = Platform::Schema.get_type(parsed.type)
            return error_response(NO_TYPE_FOUND_MESSAGE, parsed.type)
          end

          unless object = type.load_from_global_id(parsed.id).sync
            return error_response(NO_OBJECT_FOUND_MESSAGE, parsed.type)
          end

          begin
            next_global_id = object.next_global_id
            return error_response(NEXT_ID_DOES_NOT_EXIST_MESSAGE, parsed.type) if next_global_id.nil?
          rescue Platform::Errors::NotFound
            return error_response(INTERNAL_ERROR, parsed.type)
          end

          GitHub.dogstats.increment(
            "actions.twirp.get_next_global_id",
            tags: ["conversion_status:success", "type:#{parsed.type}"]
          )
          next_global_id_response(next_global_id)
        end

        def next_global_id_response(next_global_id)
          {
            next_global_id: next_global_id
          }
        end

        def error_response(message, type)
          GitHub.dogstats.increment(
            "actions.twirp.get_next_global_id",
            tags: ["conversion_status:failure", "reason:#{message}", "type:#{type}"]
          )

          log_fields = {
            "code.namespace" => self.class.name,
            "code.function" => "call",
            "gh.request_id" => GitHub.context[:request_id],
            "gh.catalog_service" => "github/actions",
            "gh.actions.request.global_id" => req.global_id,
          }.tap do |fields|
            fields["gh.actions.request.global_id.type"] = type if type
          end

          GitHub.logger.info(message, log_fields)

          Twirp::Error.not_found(message)
        end
      end
    end
  end
end
