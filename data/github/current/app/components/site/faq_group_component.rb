# typed: true
# frozen_string_literal: true

module Site
  class FaqGroupComponent < ApplicationComponent
    renders_many :items, Site::FaqItemComponent

    VERSION = "1.0.0"
    DEPENDENCIES = {
      Site::FaqItemComponent.name => Site::FaqItemComponent::VERSION
    }

    def initialize(title: nil, items: [], render: true)
      @title = title
      @items = items
      @render = render
      @digest = Digest::SHA256.hexdigest("#{@items.present? ? @items.to_json : "items"}_#{@title}#{DEPENDENCIES.to_json}")
    end

    def cache_key
      "site_faq_group_#{VERSION}_#{@digest}"
    end

    def render?
      @render
    end
  end
end
