# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class SubscriptionsServiceTest < GitHub::TestCase
    include NotifydTestHelper
    Subs = Notifyd::Proto::Subscriptions

    setup do
      @user = create(:user)
      @gist = create(:gist)
      @repo = create(:repository)
      @repo.add_member(@user)
      @issue = create(:issue, repository: @repo)
      @label1 = create(:label, repository: @repo, name: "bug")
      @label2 = create(:label, repository: @repo, name: "feature")

      GitHub.stubs(:dynamic_lab?).returns(false)
      GitHub.stubs(:notifyd_production_url).returns("http://random-url.com")
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(@notifyd_client_mock)
      @subscriptions_client_mock = mock("Subs::SubscriptionsClient")
        .responds_like_instance_of(Subs::SubscriptionsClient)
      @notifyd_client_mock.stubs(:subscriptions).returns(@subscriptions_client_mock)

      @subscription_id = 202
      @thread_subscription_response = Subs::Subscription.new({
        id: @subscription_id,
        user_id: @user.id,
        custom_fields: [
          Subs::CustomField.new(name: "thread_type", value: "gist"),
          Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
        ]
      })
    end

    context ".get_thread_subscription", skip_enterprise: true do
      test "gets thread subscription" do

        get_response = Twirp::ClientResp.new(
          data: Subs::GetResponse.new(
            subscriptions: [@thread_subscription_response]
          ),
          error: nil,
        )

        @subscriptions_client_mock
          .expects(:get)
          .with(Subs::GetRequest.new(
            user_id: @user.id,
            filter_by_custom_fields: [
              Subs::CustomField.new(name: "thread_type", value: "gist"),
              Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s)
            ]))
          .returns(get_response)

        assert Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).get_thread_subscription("gist", @gist.id)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:GetRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end


      test "returns nil if get returns error if notifyd is not the primary" do
        @subscriptions_client_mock
          .expects(:get)
          .with(
            Subs::GetRequest.new(
              user_id: @user.id,
              filter_by_custom_fields: [
                Subs::CustomField.new(name: "thread_type", value: "gist"),
                Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s)
              ]
            )
          )
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        assert_nil Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).get_thread_subscription("gist", @gist.id)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:GetRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:false"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "error:unavailable"
      end

      test "throws error if get returns error if notifyd is the primary" do
        @subscriptions_client_mock
          .expects(:get)
          .with(
            Subs::GetRequest.new(
              user_id: @user.id,
              filter_by_custom_fields: [
                Subs::CustomField.new(name: "thread_type", value: "gist"),
                Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s)
              ]
            )
          )
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        assert_raises Notifyd::NetworkHelper::APIError do
          Notifyd::SubscriptionsService.new(@user, true).get_thread_subscription("gist", @gist.id)
        end
      end
    end

    context ".save", skip_enterprise: true do
      test "saves a list of given subscriptions" do
        @subscriptions_client_mock
          .expects(:batch_replace)
          .with(Subs::BatchReplaceRequest.new(
            user_id: @user.id,
            new_subscriptions: [Subs::BatchReplaceCreateRequest.new(
              reason: "manual",
              topics: [Subs::Topic.new(type: "gist", value: @gist.id.to_s)],
              filters: [Subs::Filter.new(subject_type: "any", trigger: "any")],
              custom_fields: [
                Subs::CustomField.new(name: "category", value: "thread"),
                Subs::CustomField.new(name: "thread_type", value: "gist"),
                Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
                Subs::CustomField.new(name: "owner_type", value: "user"),
                Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
              ])],
             replace_by_custom_fields: [
               Subs::CustomField.new(name: "category", value: "thread"),
               Subs::CustomField.new(name: "thread_type", value: "gist"),
               Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
               Subs::CustomField.new(name: "owner_type", value: "user"),
               Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
             ]))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        assert Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).save([{
          reason: "manual",
          topics: [{ type: "gist", value: @gist.id.to_s }],
          filters: [{ subject_type: "any", trigger: "any" }],
          custom_fields: [
            Subs::CustomField.new(name: "category", value: "thread"),
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
            Subs::CustomField.new(name: "owner_type", value: "user"),
            Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
          ] }])

        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:BatchReplaceRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end

      test "throws an error if save API call returns error and notifyd is the primary" do
        @subscriptions_client_mock
          .expects(:batch_replace)
          .with(
            Subs::BatchReplaceRequest.new({
              user_id: @user.id,
              new_subscriptions: [Subs::BatchReplaceCreateRequest.new(
                reason: "manual",
                topics: [Subs::Topic.new(type: "gist", value: @gist.id.to_s)],
                filters: [Subs::Filter.new(subject_type: "any", trigger: "any")],
                custom_fields: [
                  Subs::CustomField.new(name: "category", value: "thread"),
                  Subs::CustomField.new(name: "thread_type", value: "gist"),
                  Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
                  Subs::CustomField.new(name: "owner_type", value: "user"),
                  Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
                ])],
               replace_by_custom_fields: [
                 Subs::CustomField.new(name: "category", value: "thread"),
                 Subs::CustomField.new(name: "thread_type", value: "gist"),
                 Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
                 Subs::CustomField.new(name: "owner_type", value: "user"),
                 Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
               ] }))
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        assert_raises Notifyd::NetworkHelper::APIError do
          assert Notifyd::SubscriptionsService.new(@user, true).save([{
            reason: "manual",
            topics: [{ type: "gist", value: @gist.id.to_s }],
            filters: [{ subject_type: "any", trigger: "any" }],
            custom_fields: [
              Subs::CustomField.new(name: "category", value: "thread"),
              Subs::CustomField.new(name: "thread_type", value: "gist"),
              Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
              Subs::CustomField.new(name: "owner_type", value: "user"),
              Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
            ] }])
        end
      end

      test "returns false if save API call returns error and notifyd is not primary" do
        @subscriptions_client_mock
          .expects(:batch_replace)
          .with(
            Subs::BatchReplaceRequest.new(
              user_id: @user.id,
              new_subscriptions: [
                Subs::BatchReplaceCreateRequest.new(
                  reason: "manual",
                  topics: [Subs::Topic.new(type: "gist", value: @gist.id.to_s)],
                  filters: [Subs::Filter.new(subject_type: "any", trigger: "any")],
                  custom_fields: [
                    Subs::CustomField.new(name: "category", value: "thread"),
                    Subs::CustomField.new(name: "thread_type", value: "gist"),
                    Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
                    Subs::CustomField.new(name: "owner_type", value: "user"),
                    Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
                  ]
                )
              ],
              replace_by_custom_fields: [
                Subs::CustomField.new(name: "category", value: "thread"),
                Subs::CustomField.new(name: "thread_type", value: "gist"),
                Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
                Subs::CustomField.new(name: "owner_type", value: "user"),
                Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
              ])
          )
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        refute Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).save([{
          reason: "manual",
          topics: [{ type: "gist", value: @gist.id.to_s }],
          filters: [{ subject_type: "any", trigger: "any" }],
          custom_fields: [
            Subs::CustomField.new(name: "category", value: "thread"),
            Subs::CustomField.new(name: "thread_type", value: "gist"),
            Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
            Subs::CustomField.new(name: "owner_type", value: "user"),
            Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
          ] }])

        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:BatchReplaceRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:false"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "error:unavailable"
      end
    end

    context ".delete", skip_enterprise: true do
      test "deletes subscriptions by given custom fields" do
        custom_fields = [
          Subs::CustomField.new(name: "category", value: "thread"),
          Subs::CustomField.new(name: "thread_type", value: "gist"),
          Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          Subs::CustomField.new(name: "owner_type", value: "user"),
          Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
        ]

        @subscriptions_client_mock
          .expects(:batch_replace)
          .with(Subs::BatchReplaceRequest.new(
          user_id: @user.id,
          new_subscriptions: [],
          replace_by_custom_fields: custom_fields))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        assert Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).delete(custom_fields)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:BatchReplaceRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end

      test "throws an error if delete API call returns error and notifyd is the primary" do

        custom_fields = [
          Subs::CustomField.new(name: "category", value: "thread"),
          Subs::CustomField.new(name: "thread_type", value: "gist"),
          Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          Subs::CustomField.new(name: "owner_type", value: "user"),
          Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
        ]

        @subscriptions_client_mock
          .expects(:batch_replace)
          .with(Subs::BatchReplaceRequest.new(
          user_id: @user.id,
          new_subscriptions: [],
          replace_by_custom_fields: custom_fields))
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        assert_raises Notifyd::NetworkHelper::APIError do
          Notifyd::SubscriptionsService.new(@user, true).delete(custom_fields)
        end
      end

      test "return false if delete API call returns error and notifyd is not primary" do
        custom_fields = [
          Subs::CustomField.new(name: "category", value: "thread"),
          Subs::CustomField.new(name: "thread_type", value: "gist"),
          Subs::CustomField.new(name: "thread_id", value: @gist.id.to_s),
          Subs::CustomField.new(name: "owner_type", value: "user"),
          Subs::CustomField.new(name: "owner_id", value: @gist.user.id.to_s),
        ]

        @subscriptions_client_mock
          .expects(:batch_replace)
          .with(Subs::BatchReplaceRequest.new(
          user_id: @user.id,
          new_subscriptions: [],
          replace_by_custom_fields: custom_fields))
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        refute Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).delete(custom_fields)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:BatchReplaceRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:false"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "error:unavailable"
      end
    end

    context ".get_thread_label_subscriptions", skip_enterprise: true, feature_enabled: :notifyd_label_subscriptions do
      test "returns label subscriptions for a thread if user is subscribed to one of the thread labels" do
        @issue.add_labels([@label1])

        get_response = Twirp::ClientResp.new(
          data: Subs::GetResponse.new(
            subscriptions: label_subscriptions(@user, @repo, @issue, @label1)
          ),
          error: nil,
        )

        @subscriptions_client_mock
        .expects(:get)
        .with(Subs::GetRequest.new(
          user_id: @user.id,
          filter_by_custom_fields: [
            { name: "repository_id", value: @repo.id.to_s },
            { name: "subject_type", value: "Issue" },
            { name: "label_id" },
          ]))
        .returns(get_response)

        label_subscriptions = Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).get_thread_label_subscriptions(@repo, @issue)
        assert_equal 1, label_subscriptions.length
        assert label_subscriptions[0].is_a?(Notifyd::LabelSubscription)
        assert label_subscriptions[0].valid?
      end

      test "returns empty label subscriptions for a thread if user is not subscribed to any of the thread labels" do
        @issue.add_labels([@label1])

        get_response = Twirp::ClientResp.new(
          data: Subs::GetResponse.new(
            subscriptions: label_subscriptions(@user, @repo, @issue, @label2)
          ),
          error: nil,
        )

        @subscriptions_client_mock
        .expects(:get)
        .with(Subs::GetRequest.new(
          user_id: @user.id,
          filter_by_custom_fields: [
            { name: "repository_id", value: @repo.id.to_s },
            { name: "subject_type", value: "Issue" },
            { name: "label_id" },
          ]))
        .returns(get_response)

        label_subscriptions = Notifyd::SubscriptionsService.new(@user, false, ["test_tag:true"]).get_thread_label_subscriptions(@repo, @issue)
        assert_equal 0, label_subscriptions.length
      end
    end
  end
end
