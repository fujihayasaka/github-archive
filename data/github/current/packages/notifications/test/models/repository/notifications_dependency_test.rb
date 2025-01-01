# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryNotificationsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  context "#subscribed_labels" do
    test "returns empty list if error returned in response" do
      status = GitHub.newsies.subscription_status(@user, @repo)

      notifyd_client_mock = mock("Notifyd::Client")
      subscriptions_client_mock = mock("Notifyd::Subscriptions::SubscriptionsClient")
      subscriptions_client_mock.stubs(:get).returns(Twirp::ClientResp.new(error: Twirp::Error.internal("Something went wrong"), data: nil))
      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)
      @repo.instance_variable_set(:@notifyd_client, notifyd_client_mock)

      assert_equal [], @repo.subscribed_labels(@user)
    end

    test "returns list of subscribed labels" do
      labels = []
      labels.push(create(:label, repository: @repo, name: "bug", color: "cccccc", description: "A problem"))
      labels.push(create(:label, repository: @repo, name: "feature", color: "cccccc", description: "A feature"))
      labels.push(create(:label, repository: @repo, name: "random", color: "cccccc", description: "Unclassified"))


      notifyd_client_mock = mock("Notifyd::Client")
      subscriptions_client_mock = mock("Notifyd::Subscriptions::SubscriptionsClient")
      subscriptions_client_mock.stubs(:get).returns(Twirp::ClientResp.new(
        data: Notifyd::Proto::Subscriptions::GetResponse.new(
          subscriptions: [
            Notifyd::Proto::Subscriptions::Subscription.new(
              user_id: @user.id, custom_fields: [
                { name: "label_id", value: labels[0].id.to_s },
                { name: "repository_id", value: @repo.id.to_s }]
            ),
            Notifyd::Proto::Subscriptions::Subscription.new(
              user_id: @user.id, custom_fields: [
                { name: "label_id", value: labels[1].id.to_s },
                { name: "repository_id", value: @repo.id.to_s }]
            ),
          ],
        ),
        error: nil # no error
      ))
      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)
      @repo.instance_variable_set(:@notifyd_client, notifyd_client_mock)

      subscribed_labels = @repo.subscribed_labels(@user)

      assert_equal 2, subscribed_labels.length
      assert_equal labels[0].name, subscribed_labels[0].name
      assert_equal labels[1].name, subscribed_labels[1].name
    end

    test "returns list of subscribed labels per user" do
      user2 = create(:user)
      @repo.add_member(user2)

      labels = []
      labels.push(create(:label, repository: @repo, name: "bug", color: "cccccc", description: "A problem"))
      labels.push(create(:label, repository: @repo, name: "feature", color: "cccccc", description: "A feature"))
      labels.push(create(:label, repository: @repo, name: "random", color: "cccccc", description: "Unclassified"))


      notifyd_client_mock = mock("Notifyd::Client")
      subscriptions_client_mock = mock("Notifyd::Subscriptions::SubscriptionsClient")

      request1 = Notifyd::Proto::Subscriptions::GetRequest.new(
        user_id: @user.id,
        filter_by_custom_fields: [
          { name: "repository_id", value: @repo.id.to_s },
          { name: "subject_type", value: "Issue" },
          { name: "label_id" },
        ],
      )
      request2 = Notifyd::Proto::Subscriptions::GetRequest.new(
        user_id: user2.id,
        filter_by_custom_fields: [
          { name: "repository_id", value: @repo.id.to_s },
          { name: "subject_type", value: "Issue" },
          { name: "label_id" },
        ],
      )

      subscriptions_client_mock.stubs(:get).with(request1).returns(Twirp::ClientResp.new(
        data: Notifyd::Proto::Subscriptions::GetResponse.new(
          subscriptions: [
            Notifyd::Proto::Subscriptions::Subscription.new(
              user_id: @user.id, custom_fields: [
                { name: "label_id", value: labels[0].id.to_s },
                { name: "repository_id", value: @repo.id.to_s }]
            ),
            Notifyd::Proto::Subscriptions::Subscription.new(
              user_id: @user.id, custom_fields: [
                { name: "label_id", value: labels[1].id.to_s },
                { name: "repository_id", value: @repo.id.to_s }]
            ),
          ],
        ),
        error: nil # no error
      ))
      subscriptions_client_mock.stubs(:get).with(request2).returns(Twirp::ClientResp.new(
        data: Notifyd::Proto::Subscriptions::GetResponse.new(subscriptions: []),
        error: nil # no error
      ))

      notifyd_client_mock.stubs(:subscriptions).returns(subscriptions_client_mock)
      @repo.instance_variable_set(:@notifyd_client, notifyd_client_mock)

      subscribed_labels = @repo.subscribed_labels(@user)

      assert_equal 2, subscribed_labels.length
      assert_equal labels[0].name, subscribed_labels[0].name
      assert_equal labels[1].name, subscribed_labels[1].name

      subscribed_labels = @repo.subscribed_labels(user2)
      assert_equal 0, subscribed_labels.length
    end

    test "returns empty if notifyd_production_url is not set" do
      GitHub.stubs(:notifyd_production_url).returns(nil)
      assert_equal [], @repo.subscribed_labels(@user)
    end
  end
end
