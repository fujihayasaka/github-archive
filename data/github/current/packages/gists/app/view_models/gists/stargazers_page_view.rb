# typed: true
# frozen_string_literal: true

module Gists
  # Controls the stargazers pages
  # eg https://github.com/gists/spicycode/:uid/stargazers
  class StargazersPageView < ShowPageView
    PER_PAGE = 51

    attr_reader :gist, :current_page

    def page_title
      "Stargazers · #{gist.title}"
    end

    def stargazers
      @stargazers ||= begin
        stargazer_ids = Stars.domain.gist_starred_user_ids(gist.id)

        User.where(id: stargazer_ids).
          order(Arel.sql("FIELD(`users`.`id`, #{stargazer_ids.join(", ")})")).
          filter_spam_for(current_user).
          paginate(page: current_page, per_page: PER_PAGE)
      end
    end
  end
end
