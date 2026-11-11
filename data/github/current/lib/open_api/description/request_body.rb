# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class RequestBody
      def initialize(request_body)
        @raw = request_body
      end

      def content
        @raw["content"]
      end

      def schema
        # We only support one media type for request bodies at the moment
        media_type     = content.keys.first
        api_media_type = Api::MediaType.new(media_type)

        # application/json or any +json suffixes
        if !(media_type == "application/json" || api_media_type.json?)
          raise "Only JSON content types are currently handled, got #{api_media_type}"
        end

        OpenApi::Description::Schema.new(content[media_type]["schema"])
      end
    end
  end
end
