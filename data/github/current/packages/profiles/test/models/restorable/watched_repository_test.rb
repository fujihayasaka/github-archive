# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableWatchedRepositoryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @user.unwatch_repo(@repo)
    @restorable = Restorable.create
  end

  test ".restore watches repository" do
    @restorable.watched_repositories.create({
      repository_id: @repo.id,
      ignored: false,
    })
    @restorable.saved(:restorable_watched_repositories)

    assert_difference("GitHub.newsies.list_subscriptions(@user, [@repo.id]).count", 1) do
      Restorable::WatchedRepository.restore(
        restorable: @restorable,
        user: @user
      )
    end

    refute GitHub.newsies.subscription_status(@user, @repo).ignored?
  end

  test ".restore ignores repository" do
    @restorable.watched_repositories.create({
      repository_id: @repo.id,
      ignored: true,
    })
    @restorable.saved(:restorable_watched_repositories)

    Restorable::WatchedRepository.restore(
      restorable: @restorable,
      user: @user
    )
    assert GitHub.newsies.subscription_status(@user, @repo).ignored?
  end

  test ".restore does not attempt to restore if subject has been deleted" do
    @restorable.watched_repositories.create({
      repository_id: @repo.id,
      ignored: true,
    })
    @restorable.saved(:restorable_watched_repositories)
    @repo.delete

    GitHub.expects(:newsies).never

    Restorable::WatchedRepository.restore(
      restorable: @restorable,
      user: @user
    )
  end

  test ".restore does not bomb if called twice" do
    @restorable.watched_repositories.create({
      repository_id: @repo.id,
      ignored: false,
    })
    Restorable::WatchedRepository.restore(
      restorable: @restorable,
      user: @user
    )
    Restorable::WatchedRepository.restore(
      restorable: @restorable,
      user: @user
    )
  end
end
