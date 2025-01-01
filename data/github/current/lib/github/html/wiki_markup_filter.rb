# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML::Pipeline filter for processing contents with GitHub::Markup
  class WikiMarkupFilter < ::HTML::Pipeline::TextFilter
    def call
      markup_sym = case context[:format]
      when :markdown
        ::GitHub::Markups::MARKUP_MARKDOWN
      when :textile
        ::GitHub::Markups::MARKUP_TEXTILE
      when :rdoc
        ::GitHub::Markups::MARKUP_RDOC
      when :org
        ::GitHub::Markups::MARKUP_ORG
      when :creole
        ::GitHub::Markups::MARKUP_CREOLE
      when :rest
        ::GitHub::Markups::MARKUP_RST
      when :asciidoc
        ::GitHub::Markups::MARKUP_ASCIIDOC
      when :pod
        ::GitHub::Markups::MARKUP_POD
      when :mediawiki
        ::GitHub::Markups::MARKUP_MEDIAWIKI
      else
        return @text
      end

      GitHub::Markup.markups[markup_sym].render(context[:path], @text, options: { commonmarker_opts: [:UNSAFE] })
    end
  end
end
