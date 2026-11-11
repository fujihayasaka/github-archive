# typed: true
# frozen_string_literal: true

module GitHub
  class BatchDeferredContentComponent < ApplicationComponent
    TAG_NAME = "batch-deferred-content"

    attr_reader :url, :inputs, :classes, :content_tag_options

    def initialize(url:, inputs: {}, classes: nil, content_tag_options: {})
      @url = url
      @inputs = inputs
      @classes = classes
      @content_tag_options = content_tag_options
    end

    def content_tag_name
      TAG_NAME
    end
  end
end
