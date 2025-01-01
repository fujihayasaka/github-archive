# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

class Conduit::RepositorySubscriptionsTest < GitHub::TestCase
  test "returns repository subscriptions" do
    user = create(:user)
    repository = create(:public_repository)
    repository2 = create(:public_repository)

    repo_list_1 = Newsies::List.new("Repository", repository.id)
    repo_list_2 = Newsies::List.new("Repository", repository2.id)
    team_list_1 = Newsies::List.new("Team", 101)
    team_list_2 = Newsies::List.new("Team", 102)

    Newsies::ListSubscription.subscribe(user.id, repo_list_1)
    Newsies::ListSubscription.subscribe(user.id, repo_list_2)
    Newsies::ListSubscription.subscribe(user.id, team_list_1)
    Newsies::ListSubscription.subscribe(user.id, team_list_2)

    subscriptions = Conduit::RepositorySubscriptions.for_user(user)
    assert_equal 2, subscriptions.count
  end

  test "returns repository subscriptions with limit" do
    user = create(:user)
    repository = create(:public_repository)
    repository2 = create(:public_repository)

    repo_list_1 = Newsies::List.new("Repository", repository.id)
    repo_list_2 = Newsies::List.new("Repository", repository2.id)

    Newsies::ListSubscription.subscribe(user.id, repo_list_1)
    Newsies::ListSubscription.subscribe(user.id, repo_list_2)

    subscriptions = Conduit::RepositorySubscriptions.for_user(user, limit: 1)
    assert_equal 1, subscriptions.count
    assert_equal repository2.id, subscriptions.first.repository_id
  end
end
