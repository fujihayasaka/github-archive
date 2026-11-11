# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class UnescapeTextLinksInputFilter < InputFilter
    def call(html)
      # Some times we get a cgi escaped string and we need to find all the
      # links and clean them up so that the search emphasis link hightlighter
      # can clean them up. Nokogiri magically did this in the old pipeline
      # this is re-implementing that in a narrow way.
      html.gsub(/(https:&#x2F;&#x2F;|http:&#x2F;&#x2F;)\S*/) { |m| CGI.unescapeHTML(m) }
    end
  end
end
