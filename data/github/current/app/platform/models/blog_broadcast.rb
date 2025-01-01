# typed: true
# frozen_string_literal: true

module Platform
  module Models
    class BlogBroadcast
      attr_reader :id, :title, :url, :content

      def initialize(id:, title:, url:, content:)
        @id = id
        @title = title
        @url = url
        @content = content
      end
    end
  end
end
