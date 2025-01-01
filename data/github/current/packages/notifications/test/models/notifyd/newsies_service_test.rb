# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NewsiesServiceTest < GitHub::TestCase
    UserStub = Struct.new(:id)

    setup do
      GitHub.stubs(:dynamic_lab?).returns(false)
      GitHub.stubs(:notifyd_production_url).returns("http://random-url.com")

      @notifyd_client_mock = mock("Notifyd::Client")
      @newsies_client_mock = mock("Notifyd::Newsies::NewsiesClient")
      @notifyd_client_mock.stubs(:newsies).returns(@newsies_client_mock)
      Notifyd.stubs(:client).returns(@notifyd_client_mock)

      @list = create(:repository)
      @user = @list.owner
    end

    context "#watch", enterprise_only: true do
      test "skips in enterprise" do
        assert_nil Notifyd::NewsiesService.new.watch(user: nil, list: nil)
      end
    end

    context "#watch", skip_enterprise: true do
      test "makes a request to watch the list" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
        }

        watch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::WatchResponse.new(params),
          error: nil,
        )

        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, Notifyd::Proto::Newsies::WatchRequest.new(params.merge(
            custom_fields: [
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
              Notifyd::Proto::Newsies::CustomField.new(name: "auto_subscription", value: "false"),
            ]
          )))
          .returns(watch_response)

        assert Notifyd::NewsiesService.new.watch(user: @user, list: @list)
      end

      test "makes a request to watch auto subscription list" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
        }

        watch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::WatchResponse.new(params),
          error: nil,
        )

        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, Notifyd::Proto::Newsies::WatchRequest.new(params.merge(
            custom_fields: [
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
              Notifyd::Proto::Newsies::CustomField.new(name: "auto_subscription", value: "true"),
            ]
          )))
          .returns(watch_response)

        assert Notifyd::NewsiesService.new.watch(user: @user, list: @list, is_auto_susbcription: true)
      end

      test "makes a request to watch the list with thread types" do
        base_params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
        }

        thread_types = %w[
          Discussion
          Issue
          PullRequest
          Release
          SecurityAlert
        ]

        watch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::WatchResponse.new(base_params),
          error: nil,
        )

        watch_request = Notifyd::Proto::Newsies::WatchRequest.new(base_params.merge(
          thread_types: [
            Notifyd::Proto::Newsies::ThreadTypes::DISCUSSION,
            Notifyd::Proto::Newsies::ThreadTypes::ISSUE,
            Notifyd::Proto::Newsies::ThreadTypes::PULL_REQUEST,
            Notifyd::Proto::Newsies::ThreadTypes::RELEASE,
            Notifyd::Proto::Newsies::ThreadTypes::SECURITY_ALERT,
          ],
          custom_fields: [
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
            Notifyd::Proto::Newsies::CustomField.new(name: "auto_subscription", value: "false"),
          ]
        ))
        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, watch_request)
          .returns(watch_response)

        assert Notifyd::NewsiesService.new.watch(user: @user, list: @list, thread_types: thread_types)
      end

      test "returns nil on error" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
          custom_fields: [
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
            Notifyd::Proto::Newsies::CustomField.new(name: "auto_subscription", value: "false"),
          ]
        }

        watch_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, Notifyd::Proto::Newsies::WatchRequest.new(params))
          .returns(watch_response)

        assert_nil Notifyd::NewsiesService.new.watch(user: @user, list: @list)
      end
    end

    context "#watch_repository", skip_enterprise: true do
      test "makes a request to watch repository" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
        }

        watch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::WatchResponse.new(params),
          error: nil,
        )

        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, Notifyd::Proto::Newsies::WatchRequest.new(params.merge(
            custom_fields: [
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
              Notifyd::Proto::Newsies::CustomField.new(name: "auto_subscription", value: "false"),
            ]
          )))
          .returns(watch_response)

        assert Notifyd::NewsiesService.new.watch(user: @user, list: @list)
      end

      test "makes a request to watch the list with thread types" do
        base_params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
        }

        thread_types = %w[
          Discussion
          Issue
          PullRequest
          Release
          SecurityAlert
        ]

        watch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::WatchResponse.new(base_params),
          error: nil,
        )

        watch_request = Notifyd::Proto::Newsies::WatchRequest.new(base_params.merge(
          thread_types: [
            Notifyd::Proto::Newsies::ThreadTypes::DISCUSSION,
            Notifyd::Proto::Newsies::ThreadTypes::ISSUE,
            Notifyd::Proto::Newsies::ThreadTypes::PULL_REQUEST,
            Notifyd::Proto::Newsies::ThreadTypes::RELEASE,
            Notifyd::Proto::Newsies::ThreadTypes::SECURITY_ALERT,
          ],
          custom_fields: [
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
          ]
        ))
        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, watch_request)
          .returns(watch_response)

        assert Notifyd::NewsiesService.new.watch_repository(user_id: @user.id,
           repository_id: @list.id,
           owner_id: @list.owner.id,
           owner_type: @list.owner.class.name.downcase,
           thread_types: thread_types)
      end

      test "returns nil on error" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
          custom_fields: [
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
          ]
        }

        watch_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
        @newsies_client_mock
          .expects(:rpc)
          .with(:Watch, Notifyd::Proto::Newsies::WatchRequest.new(params))
          .returns(watch_response)

        assert_nil Notifyd::NewsiesService.new.watch_repository(user_id: @user.id,
          repository_id: @list.id,
          owner_id: @list.owner.id,
          owner_type: @list.owner.class.name.downcase)
      end
    end

    context "#unwatch", enterprise_only: true do
      test "skips in enterprise" do
        assert_nil Notifyd::NewsiesService.new.unwatch(user: nil, lists: nil)
      end
    end

    context "#unwatch", skip_enterprise: true do
      test "makes a request to unwatch the list" do
        params = {
          user_id: @user.id,
          ref_ids: [@list.id],
          ref_type: @list.class.name,
        }

        unwatch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::UnwatchResponse.new(params),
          error: nil,
        )

        @newsies_client_mock
          .expects(:rpc)
          .with(:Unwatch, Notifyd::Proto::Newsies::UnwatchRequest.new(params))
          .returns(unwatch_response)

        assert Notifyd::NewsiesService.new.unwatch(user: @user, lists: [@list])
      end

      test "returns nil on error" do
        params = {
          user_id: @user.id,
          ref_ids: [@list.id],
          ref_type: @list.class.name,
        }

        unwatch_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
        @newsies_client_mock
          .expects(:rpc)
          .with(:Unwatch, Notifyd::Proto::Newsies::UnwatchRequest.new(params))
          .returns(unwatch_response)

        assert_nil Notifyd::NewsiesService.new.unwatch(user: @user, lists: [@list])
      end
    end

    context "#unwatch_all", enterprise_only: true do
      test "skips in enterprise" do
        assert_nil Notifyd::NewsiesService.new.unwatch_all(user_id: nil, ref_type: nil)
      end
    end

    context "#unwatch_all", skip_enterprise: true do
      test "makes a request to unwatch all the lists" do
        params = {
          user_id: 1,
          ref_type: @list.class.name,
        }

        unwatch_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::UnwatchAllResponse.new(params),
          error: nil,
        )

        @newsies_client_mock
          .expects(:rpc)
          .with(:UnwatchAll, Notifyd::Proto::Newsies::UnwatchAllRequest.new(params))
          .returns(unwatch_response)

        assert Notifyd::NewsiesService.new.unwatch_all(user_id: 1, ref_type: "Repository")
      end

      test "returns nil on error" do
        params = {
          user_id: 1,
          ref_type: @list.class.name,
        }

        unwatch_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
        @newsies_client_mock
          .expects(:rpc)
          .with(:UnwatchAll, Notifyd::Proto::Newsies::UnwatchAllRequest.new(params))
          .returns(unwatch_response)

        assert_nil Notifyd::NewsiesService.new.unwatch_all(user_id: 1, ref_type: "Repository")
      end
    end

    context "#ignore", enterprise_only: true do
      test "skips in enterprise" do
        assert_nil Notifyd::NewsiesService.new.ignore(user: nil, list: nil)
      end
    end

    context "#ignore", skip_enterprise: true do
      test "makes a request to ignore the list" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
        }

        ignore_response = Twirp::ClientResp.new(
          data: Notifyd::Proto::Newsies::IgnoreResponse.new(params),
          error: nil,
        )

        @newsies_client_mock
          .expects(:rpc)
          .with(:Ignore, Notifyd::Proto::Newsies::IgnoreRequest.new(params.merge(
            custom_fields: [
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
              Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
            ]
          )))
          .returns(ignore_response)

        assert Notifyd::NewsiesService.new.ignore(user: @user, list: @list)
      end

      test "returns nil on error" do
        params = {
          user_id: @user.id,
          ref_id: @list.id,
          ref_type: @list.class.name,
          custom_fields: [
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_id", value: @list.owner.id.to_s),
            Notifyd::Proto::Newsies::CustomField.new(name: "owner_type", value: @list.owner&.class&.name&.downcase),
          ]
        }

        ignore_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
        @newsies_client_mock
          .expects(:rpc)
          .with(:Ignore, Notifyd::Proto::Newsies::IgnoreRequest.new(params))
          .returns(ignore_response)

        assert_nil Notifyd::NewsiesService.new.ignore(user: @user, list: @list)
      end
    end
  end
end
