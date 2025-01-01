# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class MentionFilter < TextFilter
    IGNORE_PARENTS = ::HTML::Pipeline::MentionFilter::IGNORE_PARENTS.map { |p| "#{p} :text" }.join(",")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      GitHub::HTML::MentionFilter.cache_key(context)
    end

    def call(text)
      return nil unless text.html.include?("@")

      result = GitHub::HTML::MentionFilter.mentioned_logins_in(text.html) do |match, login, is_mentioned|
        next match if is_mentioned

        link = ActionController::Base.helpers.content_tag("gh:user-mention", body = nil, login: login)
        match.sub("@#{login}", link)
      end

      result if result != text.html
    end
  end
end
