# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class MaintenanceServiceTest < GitHub::TestCase
    include NotifydTestHelper
    Maint = Notifyd::Proto::Maintenance

    setup do
      GitHub.stubs(:dynamic_lab?).returns(false)
      GitHub.stubs(:notifyd_production_url).returns("http://random-url.com")
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(@notifyd_client_mock)
      @maintenance_client_mock = mock("Maint::MaintenanceClient").responds_like_instance_of(Maint::MaintenanceClient)
      @notifyd_client_mock.stubs(:maintenance).returns(@maintenance_client_mock)
    end

    context ".delete_repository", skip_enterprise: true do
      test "call delete repository for" do
        repo_id = 123

        @maintenance_client_mock
          .expects(:delete_repository)
          .with(Maint::DeleteRepositoryRequest.new({ repository_id: repo_id }))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        assert Notifyd::MaintenanceService.new.delete_repository(repo_id)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:DeleteRepositoryRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end
    end

    context ".delete_repository_for_users", skip_enterprise: true do
      test "call delete repository for users" do
        repo_id = 123
        user_ids = [33, 11, 22]

        @maintenance_client_mock
          .expects(:delete_repository_for_users)
          .with(Maint::DeleteRepositoryForUsersRequest.new({ repository_id: repo_id, user_ids: user_ids }))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        assert Notifyd::MaintenanceService.new.delete_repository_for_users(repo_id:, user_ids:)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:DeleteRepositoryForUsersRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end
    end

    context ".delete_user", skip_enterprise: true do
      test "call delete user" do
        user_id = 123

        @maintenance_client_mock
          .expects(:delete_user)
          .with(Maint::DeleteUserRequest.new({ user_id: user_id }))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        assert Notifyd::MaintenanceService.new.delete_user(user_id)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:DeleteUserRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end
    end

    context ".delete_user_repositories", skip_enterprise: true do
      test "call delete user repositories" do
        user_id = 123
        repo_ids = [33, 11, 22]

        @maintenance_client_mock
          .expects(:delete_user_repositories)
          .with(Maint::DeleteUserRepositoriesRequest.new({ user_id: user_id, repository_ids: repo_ids }))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        assert Notifyd::MaintenanceService.new.delete_user_repositories(user_id:, repo_ids:)
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:DeleteUserRepositoriesRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end
    end
  end
end
