# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class EmailIssueMentionFilter < InputFilter
    def self.cache_key(context)
      GitHub::HTML::IssueMentionFilter.cache_key(context)
    end

    def call(string)
      doc = Nokogiri::HTML.fragment(string)
      GitHub::HTML::IssueMentionFilter.new(doc, context, result).call.to_html
    end
  end
end
