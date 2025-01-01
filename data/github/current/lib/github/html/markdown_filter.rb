# typed: true
# frozen_string_literal: true
# From https://github.com/jch/html-pipeline/pull/274/files.

module GitHub
  module HTML
    remove_const :MarkdownFilter if const_defined? :MarkdownFilter

    # HTML Filter that converts Markdown text into HTML and converts into a
    # DocumentFragment. This is different from most filters in that it can take a
    # non-HTML as input. It must be used as the first filter in a pipeline.
    #
    # Context options:
    #   :gfm      => false    Disable GFM line-end processing
    #
    # This filter does not write any additional information to the context hash.
    class MarkdownFilter < ::HTML::Pipeline::TextFilter
      def initialize(text, context = nil, result = nil)
        super text, context, result
        @text = @text.gsub "\r", ""
      end

      EXTENSIONS = [:table, :strikethrough, :tagfilter, :autolink]

      # Convert Markdown to HTML using the best available implementation
      # and convert into a DocumentFragment.
      def call
        parse_options = :DEFAULT
        parse_options = :LIBERAL_HTML_TAG if context[:liberal_html_tag]

        doc = CommonMarker.render_doc(@text, parse_options, EXTENSIONS)
        options = [:UNSAFE, :GITHUB_PRE_LANG]
        options << :HARDBREAKS if context[:gfm] != false
        # scrub the result of to_html, because an invalid UTF-8 character could be decoded from it's HTML encoded
        # counterpart, e.g. &#xFFFE;
        html = doc.to_html(options, EXTENSIONS).scrub
        html.rstrip!
        html
      end
    end
  end
end
