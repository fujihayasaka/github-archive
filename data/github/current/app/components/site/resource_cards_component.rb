# typed: true
# frozen_string_literal: true

module Site
  class ResourceCardsComponent < ApplicationComponent
    renders_many :cards, Site::CardComponent

    VERSION = "1.0.0"
    DEPENDENCIES = {
      Site::CardComponent.name => Site::CardComponent::VERSION
    }

    def initialize(header: nil, classes: nil, cards: nil, cache: true, cache_version: 1)
      @header = header
      @classes = classes
      @cards = cards
      @cache_version = cache_version
    end

    def cache_key
      digest = Digest::SHA256.hexdigest("#{@header}#{@classes}#{@cards.present? ? cards.to_json : ""}#{@cache_version}#{DEPENDENCIES.to_json}")
      "site_resource_cards_#{VERSION}_#{digest}"
    end
  end
end
