# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # When part of link text is <em>emphasized</em> through a search hit,
  # Rinku (AutoLinkFilter) breaks the link on the <em> tag, leading to unintended results.
  class LinkEmphasisFilter < InputFilter
    def call(text)
      text.gsub(/(https:\/\/|http:\/\/)\S*<\/em>/) { |m| m.gsub(/<\/*em>/, "") }
    end
  end
end
