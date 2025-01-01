# typed: true
# frozen_string_literal: true

module Sessions
  class AuthenticationWrapperComponent < ApplicationComponent
    renders_one :header
    renders_one :body
    renders_one :footer

    attr_reader :classes, :html_attributes, :header_classes, :body_classes, :footer_classes

    def initialize(classes: nil, id: nil, html_attributes: {}, header_classes: "", body_classes: "", footer_classes: "")
      @classes = classes
      @html_attributes = html_attributes.is_a?(Hash) ? html_attributes : {}
      @header_classes = header_classes
      @body_classes = body_classes
      @footer_classes = footer_classes
    end
  end
end
