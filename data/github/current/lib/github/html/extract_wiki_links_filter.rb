# typed: true
# frozen_string_literal: true

require "digest/sha2"

module GitHub::HTML
  # Extract all tags into the tagmap and replace with placeholders.
  #
  # Returns the placeholder'd String data.
  class ExtractWikiLinksFilter < ::HTML::Pipeline::TextFilter
    Regex = /(.?)\[\[(.+?)\]\]([^\[]?)/

    def call
      result[:wiki_links] = {}
      return @text if context[:page].format == :asciidoc
      @text = self.class.operate_on_text(@text, result)
    end

    def self.operate_on_text(text, result)
      text.gsub(Regex) do
        if $1 == "'" && $3 != "'"
          "[[#{$2}]]#{$3}"
        elsif $2.include?("][")
          if $2[0..4] == "file:"
            pre = $1
            post = $3
            parts = $2.split("][")
            parts[0][0..4] = ""
            link = "#{parts[1]}|#{parts[0].sub(/\.org/, '')}"
            id = Digest::SHA256.hexdigest(link)
            result[:wiki_links][id] = link
            "#{pre}#{id}#{post}"
          else
            $&
          end
        else
          id = Digest::SHA256.hexdigest($2)
          result[:wiki_links][id] = $2
          "#{$1}#{id}#{$3}"
        end
      end
    end
  end
end
