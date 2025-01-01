# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class EmailTeamMentionFilter < InputFilter
    def call(string)
      doc = Nokogiri::HTML.fragment(string)
      GitHub::HTML::TeamMentionFilter.new(doc, context, result).call.to_html
    end
  end
end
