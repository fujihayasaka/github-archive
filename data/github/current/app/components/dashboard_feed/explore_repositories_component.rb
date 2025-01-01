# typed: strict
# frozen_string_literal: true

class DashboardFeed::ExploreRepositoriesComponent < ApplicationComponent
  private

  sig { returns(String) }
  def avatar_url
    helpers.avatar_url_for(current_user, 40)
  end

  sig { returns(T::Hash[Symbol, String]) }
  def repo
    {
      owner: "actions",
      name: "cache",
      description: "Cache dependencies and build outputs in GitHub Actions",
      language: "TypeScript",
      stargazer_count: helpers.social_count(4400),
    }
  end
end
