# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableRepositoryStarTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @restorable = Restorable.create
  end

  test ".backup persists RepositoryStar models with partial data" do
    assert_difference(-> { Restorable::RepositoryStar.count }, 1) do
      Restorable::RepositoryStar.backup(restorable: @restorable, repositories: [@repo])
    end

    restorable_star = @restorable.repository_stars.sole
    assert_equal @repo.id, restorable_star.repository_id
    assert_nil restorable_star.user_id
    assert_nil restorable_star.original_created_at
  end

  test ".backup_from_stars persists RepositoryStar models" do
    ts = DateTime.parse("2025-01-01")
    star_entity = StarEntity.new(
      id: nil,
      starrable_id: @repo.id,
      starrable_type: "Repository",
      user_id: @user.id,
      created_at: ts,
      user_hidden: nil,
    )

    assert_difference(-> { Restorable::RepositoryStar.count }, 1) do
      Restorable::RepositoryStar.backup_from_stars(restorable: @restorable, stars: [star_entity])
    end

    restorable_star = @restorable.repository_stars.sole
    assert_equal @repo.id, restorable_star.repository_id
    assert_equal @user.id, restorable_star.user_id
    assert_equal ts, restorable_star.original_created_at
  end

  test ".restore stars repository as user" do
    @restorable.repository_stars.create(repository_id: @repo.id)
    @restorable.saved(:restorable_repository_stars)

    assert_difference("Star.count", 1) do
      Restorable::RepositoryStar.restore(
        restorable: @restorable,
        user: @user
      )
    end
  end

  test ".restore skips repositories that have been removed" do
    @restorable.repository_stars.create(repository_id: @repo.id)
    @restorable.saved(:restorable_repository_stars)
    @repo.destroy

    assert_difference("Star.count", 0) do
      Restorable::RepositoryStar.restore(
        restorable: @restorable,
        user: @user
      )
    end
  end

  test ".restore does not bomb when called twice" do
    @restorable.repository_stars.create(repository_id: @repo.id)
    Restorable::RepositoryStar.restore(
      restorable: @restorable,
      user: @user
    )
    Restorable::RepositoryStar.restore(
      restorable: @restorable,
      user: @user
    )
  end
end
