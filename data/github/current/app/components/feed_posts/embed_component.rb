# typed: true
# frozen_string_literal: true

module FeedPosts
  class EmbedComponent < ApplicationComponent
    attr_reader :result

    def initialize(result:)
      @result = result
    end

    def url
      result.url
    end

    def title
      result.title
    end

    def description
      result.description
    end

    def image
      result.image
    end
  end
end
