# typed: true
# frozen_string_literal: true

require "cgi"
require "gemoji"
require_relative "../../github/goomba/colon_emojiable"

module HTML
  class Pipeline
    # HTML filter that replaces :emoji: with images.
    #
    # Context:
    #   :asset_root (required) - base url to link to emoji sprite
    #   :asset_path (optional) - url path to link to emoji sprite. :file_name can be used as a placeholder for the sprite file name. If no asset_path is set "emoji/:file_name" is used.
    #   :ignored_ancestor_tags (optional) - Tags to stop the emojification. Node has matched ancestor HTML tags will not be emojified. Default to pre, code, and tt tags. Extra tags please pass in the form of array, e.g., %w(blockquote summary).
    #   :img_attrs (optional) - Attributes for generated img tag. E.g. Pass { "draggble" => true, "height" => nil } to set draggable attribute to "true" and clear height attribute of generated img tag.
    class EmojiFilter < Filter
      extend T::Sig
      include ::GitHub::Goomba::ColonEmojiable

      Context = T.type_alias { T::Hash[Symbol, T.untyped] }
      DefaultImageAttrs = T.type_alias { T::Hash[String, String] }

      DEFAULT_IGNORED_ANCESTOR_TAGS = %w(pre code tt)

      sig { params(context: Context).returns(String) }
      def self.cache_key(context)
        image_attrs = context[:image_attrs]&.to_s
        ignored_ancestor_tags = context[:ignored_ancestor_tags]&.join(",")
        [
          "emoji_asset_root=#{context[:asset_root]}",
          ("emoji_asset_path=#{context[:asset_path]}" if context[:asset_path]),
          ("image_attrs=#{image_attrs}" if image_attrs),
          ("ignored_ancestor_tags=#{ignored_ancestor_tags}" if ignored_ancestor_tags),
        ].reject(&:blank?).join(":")
      end

      sig { returns(::Nokogiri::HTML4::DocumentFragment) }
      def call
        doc.search('.//text()').each do |node|
          content = node.to_html
          next if probably_not_a_colon_emoji?(content)
          next if has_ancestor?(node, ignored_ancestor_tags)
          html = emoji_image_filter(content)
          next if html == content
          node.replace(html)
        end
        doc
      end

      # Implementation of validate hook.
      # Errors should raise exceptions or use an existing validator.
      sig { void }
      def validate
        needs :asset_root
      end

      # Replace :emoji: with corresponding images.
      #
      # text - String text to replace :emoji: in.
      #
      # Returns a String with :emoji: replaced with images.
      sig { params(text: String).returns(String) }
      def emoji_image_filter(text)
        text.gsub(emoji_pattern) do |match|
          emoji_image_tag($1)
        end
      end

      # The base url to link emoji sprites
      #
      # Raises ArgumentError if context option has not been provided.
      # Returns the context's asset_root.
      sig { returns(T.nilable(String)) }
      def asset_root
        context[:asset_root]
      end

      # The url path to link emoji sprites
      #
      # :file_name can be used in the asset_path as a placeholder for the sprite file name. If no asset_path is set in the context "emoji/:file_name" is used.
      # Returns the context's asset_path or the default path if no context asset_path is given.
      sig { params(name: String).returns(String) }
      def asset_path(name)
        if context[:asset_path]
          context[:asset_path].gsub(":file_name", emoji_filename(name))
        else
          File.join("emoji", emoji_filename(name))
        end
      end

      private

      # Build an emoji image tag
      sig { params(name: String).returns(String) }
      def emoji_image_tag(name)
        require "active_support/core_ext/hash/indifferent_access"
        html_attrs =
          default_img_attrs(name).
            merge!((context[:img_attrs] || {}).with_indifferent_access).
            map { |attr, value| !value.nil? && %(#{attr}="#{value.respond_to?(:call) && value.call(name) || value}") }.
            reject(&:blank?).join(" ".freeze)

        "<img #{html_attrs}>"
      end

      # Default attributes for img tag
      sig { params(name: String).returns(DefaultImageAttrs) }
      def default_img_attrs(name)
        {
          "class" => "emoji".freeze,
          "title" => ":#{name}:",
          "alt" => ":#{name}:",
          "src" => "#{emoji_url(name)}",
          "height" => "20".freeze,
          "width" => "20".freeze,
          "align" => "absmiddle".freeze,
        }
      end

      sig { params(name: String).returns(String) }
      def emoji_url(name)
        File.join(asset_root, asset_path(name))
      end

      # Build a regexp that matches all valid :emoji: names.
      sig { returns(Regexp) }
      def self.emoji_pattern
        @emoji_pattern ||= Regexp.new(/:(#{emoji_names.map { |name| Regexp.escape(name) }.join('|')}):/, timeout: 5)
      end

      sig { returns(Regexp) }
      def emoji_pattern
        self.class.emoji_pattern
      end

      sig { returns(T::Array[String]) }
      def self.emoji_names
        Emoji.all.map(&:aliases).flatten.sort
      end

      sig { params(name: String).returns(String) }
      def emoji_filename(name)
        Emoji.find_by_alias(name).image_filename
      end

      # Return ancestor tags to stop the emojification.
      #
      # @return [Array<String>] Ancestor tags.
      sig { returns(T::Array[String]) }
      def ignored_ancestor_tags
        if context[:ignored_ancestor_tags]
          DEFAULT_IGNORED_ANCESTOR_TAGS | context[:ignored_ancestor_tags]
        else
          DEFAULT_IGNORED_ANCESTOR_TAGS
        end
      end
    end
  end
end
