# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroStarsRepositoryVisibilityJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @repo1 = create(:private_repository)
    @repo2 = create(:public_repository)
    @user1 = create(:user)
    @user2 = create(:user)
  end

  setup do
    Stars.domain.star_repository(repository: @repo1, user: @user1)
    Stars.domain.star_repository(repository: @repo2, user: @user1)
    Stars.domain.star_repository(repository: @repo1, user: @user2)
    Stars.domain.star_repository(repository: @repo2, user: @user2)
  end

  test "it works" do
    message = {
      actor_id: @repo1.owner_id,
      old_visibility: "PUBLIC",
      new_visibility: "PRIVATE",
    }

    perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")

    refute Stars.domain.repo_starred_by_user?(@repo1.id, @user1.id)
    refute Stars.domain.repo_starred_by_user?(@repo1.id, @user2.id)
    assert Stars.domain.repo_starred_by_user?(@repo2.id, @user1.id)
    assert Stars.domain.repo_starred_by_user?(@repo2.id, @user2.id)
  end
end
