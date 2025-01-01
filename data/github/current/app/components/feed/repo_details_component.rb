# typed: true
# frozen_string_literal: true

module Feed
  class RepoDetailsComponent < ApplicationComponent
    attr_reader :item

    delegate :repository, to: :item

    def initialize(item:)
      @item = item
    end

    def render?
      repository.present? && (
        repository.stargazer_count > 0 || repository.primary_language_name.present?
      )
    end

    private

    def render_link_to_repo_stargazers(current_user: nil)
      return if repository.stargazer_count.zero?

      user_starred_repo = current_user && Stars.domain.repo_starred_by_user?(repository.id, current_user.id)
      stargazer_count_with_icon = safe_join([
        primer_octicon(user_starred_repo ? :"star-fill" : :star, mr: 1),
        helpers.social_count(repository.stargazer_count),
      ])

      render(Primer::Beta::Link.new(
        href: gh_stargazers_path(repository),
        data: helpers.feed_clicks_hydro_attrs(click_target: "stargazers", feed_item: item),
        scheme: :primary,
        underline: false,
        muted: true,
        mr: 3,
        test_selector: "repo-stargazer-link"
      )) { stargazer_count_with_icon }
    end
  end
end
