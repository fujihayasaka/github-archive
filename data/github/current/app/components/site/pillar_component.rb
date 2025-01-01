# typed: true
# frozen_string_literal: true

module Site
  class PillarComponent < ApplicationComponent
    renders_one :icon
    VERSION = "1.0.0"
    DEPENDENCIES = {
      Site::LinkComponent.name => Site::LinkComponent::VERSION
    }

    def initialize(octicon: nil, header: "Header", text: "Paragraph", link: nil, header_tag: :h3, cache: true, cache_version: 1)
      @octicon = octicon
      @header = header
      @text = text
      @link = link
      @header_tag = header_tag
      @cache = cache
      @cache_version = cache_version
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@octicon}#{@header}#{@text}#{@link.present? ? @link.to_json : ""}#{@header_tag}#{@cache_version}#{DEPENDENCIES.to_json}}")
      "site_pillar_#{VERSION}_#{digest}"
    end

  end
end
