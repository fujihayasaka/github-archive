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

    @repo1.add_member(@user1)
    @repo1.add_member(@user2)
  end

  setup do
    Stars.domain.star_repository(repository: @repo1, user: @user1)
    Stars.domain.star_repository(repository: @repo2, user: @user1)
    Stars.domain.star_repository(repository: @repo1, user: @user2)
    Stars.domain.star_repository(repository: @repo2, user: @user2)

    @repo1.remove_member(@user1)
    @repo1.remove_member(@user2)
  end

  test "it works" do
    message = {
      repository_id: @repo1.id,
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

  test "it stores restorable stars if a restoration is underway" do
    enable_feature_flag(:alt_hydro_stars_repository_visibility)
    enable_feature_flag(:visibility_change_recovery_storage)

    underway = Restorable::VisibilityChangedRepository.ensure_started(@repo1)

    message = {
      repository_id: @repo1.id,
      actor_id: @repo1.owner_id,
      old_visibility: "PUBLIC",
      new_visibility: "PRIVATE",
    }

    perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")

    restorable = Restorable::VisibilityChangedRepository.most_recent(@repo1.id).sole
    assert_equal restorable, underway
    restorable_stars = T.must(restorable.restorable).repository_stars.to_a
    assert_equal [@repo1.id], restorable_stars.pluck(:repository_id).uniq
    assert_equal [restorable.restorable_id], restorable_stars.pluck(:restorable_id).uniq
    assert_same_elements [@user1.id, @user2.id], restorable_stars.pluck(:user_id)
  end

  test "it does not store restorable stars if no restoration is underway" do
    enable_feature_flag(:alt_hydro_stars_repository_visibility)
    enable_feature_flag(:visibility_change_recovery_storage)

    message = {
      repository_id: @repo1.id,
      actor_id: @repo1.owner_id,
      old_visibility: "PUBLIC",
      new_visibility: "PRIVATE",
    }

    perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")

    assert_empty Restorable::VisibilityChangedRepository.most_recent(@repo1.id)
  end

  test "it does not store restorable stars if the feature flag is disabled" do
    enable_feature_flag(:alt_hydro_stars_repository_visibility)
    disable_feature_flag(:visibility_change_recovery_storage)

    underway = Restorable::VisibilityChangedRepository.ensure_started(@repo1)

    message = {
      repository_id: @repo1.id,
      actor_id: @repo1.owner_id,
      old_visibility: "PUBLIC",
      new_visibility: "PRIVATE",
    }

    perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")

    restorable = Restorable::VisibilityChangedRepository.most_recent(@repo1.id).sole
    assert_equal restorable, underway
    assert_empty T.must(restorable.restorable).repository_stars
  end

  context "#with_star_batch" do
    # We can't test this method directly (even if it was public) because Hydro jobs are not trivial to instantiate.
    # Instead, we exercise it by covering each branch in the method and asserting the observable external behavior.

    test "yields a single batch of stars" do
      enable_feature_flag(:alt_hydro_stars_repository_visibility)

      message = { repository_id: @repo1.id, actor_id: @repo1.owner_id }
      perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")

      Stars.domain.reset_caches
      refute Stars.domain.repo_starred_by_user?(@repo1.id, @user1.id)
      refute Stars.domain.repo_starred_by_user?(@repo1.id, @user2.id)
    end

    test "yields multiple batches of stars ending with a partial batch" do
      enable_feature_flag(:alt_hydro_stars_repository_visibility)

      # 7 total users and stars; 2 full batches of 3 and 1 batch of 1.
      # This hits the star_batch.size < BATCH_SIZE return condition.
      other_users = create_list(:user, 5) do |user|
        @repo1.add_member(user)
        Stars.domain.star_repository(repository: @repo1, user: user)
        @repo1.remove_member(user)
      end

      message = { repository_id: @repo1.id, actor_id: @repo1.owner_id }
      stub_const(HydroStarsRepositoryVisibilityJob, :BATCH_SIZE, 3) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")
      end

      Stars.domain.reset_caches
      ([@user1, @user2] + other_users).each do |user|
        refute Stars.domain.repo_starred_by_user?(@repo1.id, user.id)
      end
    end

    test "yields multiple batches of stars ending with a full batch" do
      enable_feature_flag(:alt_hydro_stars_repository_visibility)

      # 6 total users and stars; 2 full batches of 3.
      # This hits the star_batch.empty? return condition.
      other_users = create_list(:user, 4) do |user|
        @repo1.add_member(user)
        Stars.domain.star_repository(repository: @repo1, user: user)
        @repo1.remove_member(user)
      end

      message = { repository_id: @repo1.id, actor_id: @repo1.owner_id }
      stub_const(HydroStarsRepositoryVisibilityJob, :BATCH_SIZE, 3) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")
      end

      Stars.domain.reset_caches
      ([@user1, @user2] + other_users).each do |user|
        refute Stars.domain.repo_starred_by_user?(@repo1.id, user.id)
      end
    end

    test "stops yielding stars when the repository is no longer private" do
      enable_feature_flag(:alt_hydro_stars_repository_visibility)

      # Doing this the Wrong Way :tm: to avoid unwanted side effects.
      # This artificially hits the (yield star_batch) == :stop return condition.
      @repo1.update!(public: true)

      message = { repository_id: @repo1.id, actor_id: @repo1.owner_id }
      perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_stars_repository_visibility")

      Stars.domain.reset_caches
      assert Stars.domain.repo_starred_by_user?(@repo1.id, @user1.id)
      assert Stars.domain.repo_starred_by_user?(@repo1.id, @user2.id)
    end
  end
end
