# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class Responses
      def initialize(responses)
        @responses = responses
      end

      def has_status?(status)
        @responses.key?(status.to_s)
      end

      def content_for(status)
        response = @responses[status.to_s]["content"]
      end

      def schema_for(status:, media_type:)
        return unless content = content_for(status)
        return unless content.key?(media_type)

        api_media_type = Api::MediaType.new(media_type)

        # application/json or any +json suffixes
        return if !(media_type == "application/json" || api_media_type.json?)

        OpenApi::Description::Schema.new(content.fetch(media_type)["schema"])
      end
    end
  end
end
