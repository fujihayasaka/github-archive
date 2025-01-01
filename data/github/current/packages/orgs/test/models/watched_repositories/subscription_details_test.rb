# typed: true
# frozen_string_literal: true

require "test_helper"

class WatchedRepositoriesSubscriptionDetailsTest < GitHub::TestCase
  SubscriptionMock = Struct.new(:list_id, :ignored?)

  def described_class
    WatchedRepositories::SubscriptionDetails
  end

  context ".decorate_collection with an empty collection" do
    test "returns an empty collection" do
      decorated_collection = described_class.decorate_collection([])

      assert_empty decorated_collection
    end
  end

  context ".decorate_collection with no subscriptions list and filtering" do
    test "returns an empty collection" do
      ignored = build(:repository, id: 1)
      watched = build(:repository, id: 2)
      neither = build(:repository, id: 3)
      repositories = [ignored, watched, neither]

      decorated_collection = described_class.decorate_collection(
        repositories,
        subscriptions: [],
      )

      assert_empty decorated_collection
    end
  end

  context ".decorate_collection with no subscriptions list and no filtering" do
    test "decorates repos with @ignored status" do
      ignored = build(:repository, id: 1)
      watched = build(:repository, id: 2)
      neither = build(:repository, id: 3)
      repositories = [ignored, watched, neither]
      subscriptions = [
        SubscriptionMock.new(list_id: 1, ignored?: true),
        SubscriptionMock.new(list_id: 2, ignored?: false),
      ]

      decorated_collection = described_class.decorate_collection(
        repositories,
        subscriptions: subscriptions,
        include_non_subscribed: true,
      )

      assert_equal 3, decorated_collection.count
      assert_equal ignored,
        decorated_collection.find { |repo| repo.ignored == true }
      assert_equal watched,
        decorated_collection.find { |repo| repo.ignored == false }
      assert_equal neither,
        decorated_collection.find { |repo| repo.ignored.nil? }
    end
  end

  context ".decorate_collection with a subscriptions object and filtering" do
    test "filters out non-subscribed repos" do
      ignored = build(:repository, id: 1)
      watched = build(:repository, id: 2)
      neither = build(:repository, id: 3)
      repositories = [ignored, watched, neither]

      subscriptions = [
        SubscriptionMock.new(list_id: 1, ignored?: true),
        SubscriptionMock.new(list_id: 2, ignored?: false),
      ]

      decorated_collection = described_class.decorate_collection(
        repositories,
        subscriptions: subscriptions,
      )

      assert_equal 2, decorated_collection.count
      assert_equal ignored,
        decorated_collection.find { |repo| repo.ignored == true }
      assert_equal watched,
        decorated_collection.find { |repo| repo.ignored == false }
    end
  end
end
