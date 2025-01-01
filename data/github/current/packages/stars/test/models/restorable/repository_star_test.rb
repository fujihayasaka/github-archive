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
