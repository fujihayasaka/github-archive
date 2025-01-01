# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  class Wrapper
    def initialize(element_name, attributes = nil)
      @element_name = element_name
      @attributes = attributes
      @authorized_content = @unauthorized_content = ""
    end

    def authorized
      additional_content = yield
      @authorized_content += additional_content.is_a?(String) ? additional_content : additional_content.try(:to_html) || ""
    end

    def unauthorized
      additional_content = yield
      @unauthorized_content += additional_content.is_a?(String) ? additional_content : additional_content.try(:to_html) || ""
    end

    def authorized_content
      return @authorized_content if @authorized_content.is_a?(String)
      @authorized_content.try(:to_html) || ""
    end

    def unauthorized_content
      return @unauthorized_content if @unauthorized_content.is_a?(String)
      @unauthorized_content.try(:to_html) || ""
    end

    def to_html
      ActionController::Base.helpers.content_tag(@element_name, @attributes) do
        [
          ActionController::Base.helpers.content_tag(
            GitHub::Goomba::Reference::AUTHORIZED_ELEMENT,
            authorized_content.html_safe # rubocop:disable Rails/OutputSafety
          ),
          ActionController::Base.helpers.content_tag(
            GitHub::Goomba::Reference::UNAUTHORIZED_ELEMENT,
            unauthorized_content.html_safe # rubocop:disable Rails/OutputSafety
          )
        ].join.html_safe # rubocop:disable Rails/OutputSafety
      end
    end
    alias to_s to_html

    def to_document_fragment
      Goomba::DocumentFragment.new(to_html)
    end
  end
end
