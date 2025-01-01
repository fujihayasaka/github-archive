# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedWorkSearchResultsComponent < ApplicationComponent
  def initialize(repositories:, currently_featured_repos:, sponsorable_login:)
    @repositories = repositories
    @currently_featured_repos = currently_featured_repos
    @sponsorable_login = sponsorable_login
  end

  private

  attr_reader :repositories, :currently_featured_repos, :sponsorable_login
end
