# typed: false
# frozen_string_literal: true

require "emoji"

module GitHub
  module Emoji
    extend self

    # Yields each Emoji::Character instance
    def each(&block)
      ::Emoji.all.each(&block)
    end

    # Enumerates through all emoji aliases and yields:
    # 1. the alias as String; and
    # 2. its corresponding Emoji::Character instance.
    def each_by_alias
      return to_enum(__method__) unless block_given?
      index = index_by_alias
      index.keys.sort.each do |name|
        yield(name, index.fetch(name))
      end
    end

    def index_by_alias
      ::Emoji.all.each_with_object({}) do |emoji, map|
        emoji.aliases.each do |name|
          map[name] = emoji
        end
      end
    end

    def asset_path(name)
      File.join("emoji", ::Emoji.find_by_alias(name).image_filename)
    end

    def for_editor
      url_prefix = GitHub.asset_host_url
      url_prefix = GitHub.url if url_prefix.blank?
      emojis = each_by_alias.each_with_object({}) do |(name, emoji), all|
        all[name] = ["#{url_prefix}/images/icons/emoji/#{emoji.image_filename}?v8"]
        if emoji.unicode_aliases.present?
          all[name] << emoji.unicode_aliases.first
        end
      end
      emojis
    end
  end
end
