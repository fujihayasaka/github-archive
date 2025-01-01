# typed: true
# frozen_string_literal: true

# rubocop:disable Style/HashSyntax

require "test_helper"

class DelegatedBypassServiceTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @admin = create(:user)

    @org = create(:business_plus_organization, admin: @admin)
    @org_owned_repo = create(:repository, owner: @org)
    @org.add_member(@user)

    @team = create(:team, organization: @org, privacy: :closed)
  end

  setup do
    @reviewer = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(
      id: 1,
      owner_id: @org_owned_repo.id,
      owner_scope: :REPOSITORY_SCOPE,
      reviewer_id: @team.id,
      reviewer_type: :TEAM
    )
  end

  context "add_bypass_reviewer" do
    test "returns true on a successful request" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerResponse.new)
      data.stubs(:bypass_reviewer).returns({ id: 1 })
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:add_bypass_reviewer).returns(response)

      result, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(@repo.id, :repository, nil, @team.id, "TEAM", @user.id)
      refute_nil result
      assert_nil error_message
    end

    test "returns an error on a nil response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:add_bypass_reviewer).returns(nil)

      result, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(@repo.id, :repository, nil, @team.id, "TEAM", @user.id)
      assert_nil result
      assert_equal error_message, "An error has occurred while attempting to add the bypass reviewer."
    end

    test "returns an error on an error response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerResponse.new)
      data.stubs(:bypass_reviewer).returns(nil)
      error = mock("error")
      error.stubs(:present?).returns(true)
      error.stubs(:msg).returns("Internal Server Error")
      response = stub(:data => data, :error => error)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:add_bypass_reviewer).returns(response)

      result, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(@repo.id, :repository, nil, @team.id, "TEAM", @user.id)
      assert_nil result
      assert_equal error_message, "Internal Server Error"
    end

    test "returns an error if empty response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerResponse.new)
      data.stubs(:bypass_reviewer).returns(nil)
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:add_bypass_reviewer).returns(response)

      result, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(@repo.id, :repository, nil, @team.id, "TEAM", @user.id)
      assert_nil result
      assert_equal error_message, "Failed to add bypass reviewer."
    end

    context "instrumentation" do
      test "emits event in audit log when bypass reviewer is added to repo" do
        data = mock("data")
        data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerResponse.new)
        data.stubs(:bypass_reviewer).returns({ id: 1 })
        response = stub(:data => data, :error => nil)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:add_bypass_reviewer).returns(response)

        GitHub.expects(:instrument).with(
          "repository_secret_scanning_push_protection_bypass_list.add",
          {
            actor: @user.id,
            reviewer_id: @team.id,
            security_configuration_id: 2,
            reviewer_type: "TEAM",
            repo: @repo
          }
        ).once

        result, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(@repo.id, :REPOSITORY_SCOPE, 2, @team.id, "TEAM", @user.id)
      end

      test "emits event in audit log when bypass reviewer is added to org" do
        data = mock("data")
        data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerResponse.new)
        data.stubs(:bypass_reviewer).returns({ id: 1 })
        response = stub(:data => data, :error => nil)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:add_bypass_reviewer).returns(response)

        GitHub.expects(:instrument).with(
          "org_secret_scanning_push_protection_bypass_list.add",
          {
            actor: @user.id,
            reviewer_id: @team.id,
            security_configuration_id: 2,
            reviewer_type: "TEAM",
            org: @org
          }
        ).once

        result, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(@org.id, :ORGANIZATION_SCOPE, 2, @team.id, "TEAM", @user.id)
      end
    end
  end

  context "remove_bypass_reviewer" do
    test "returns nil if successful" do
      error = mock("error")
      error.stubs(:present?).returns(false)
      response = stub(:error => error)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewer).returns(response)

      error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(@team.id, @org_owned_repo.id, :repository, @user.id)
      assert_nil error_message
    end

    test "returns an error on a nil response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewer).returns(nil)

      error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(@team.id, @org_owned_repo.id, :repository, @user.id)
      assert_equal error_message, "An error has occurred while attempting to delete the bypass reviewer."
    end

    test "returns an error on an error response" do
      error = mock("error")
      error.stubs(:present?).returns(true)
      error.stubs(:msg).returns("Internal Server Error")
      response = stub(:error => error)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewer).returns(response)

      error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(@team.id, @org_owned_repo.id, :repository, @user.id)
      assert_equal error_message, "Internal Server Error"
    end

    context "instrumentation" do
      test "emits event in audit log when bypass reviewer is removed from repo" do
        error = mock("error")
        error.stubs(:present?).returns(false)
        response = stub(:error => error)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewer).returns(response)

        GitHub.expects(:instrument).with(
          "repository_secret_scanning_push_protection_bypass_list.remove",
          {
            actor: @user.id,
            bypass_reviewer_id: @team.id,
            repo: @org_owned_repo
          }
        ).once

        error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(@team.id, @org_owned_repo.id, :repository, @user.id)
      end

      test "emits event in audit log when bypass reviewer is removed from org" do
        error = mock("error")
        error.stubs(:present?).returns(false)
        response = stub(:error => error)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewer).returns(response)

        GitHub.expects(:instrument).with(
          "org_secret_scanning_push_protection_bypass_list.remove",
          {
            actor: @user.id,
            bypass_reviewer_id: @team.id,
            org: @org
          }
        ).once

        error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(@team.id, @org.id, :organization, @user.id)
      end
    end
  end

  context "remove_bypass_reviewers_for_source" do
    test "returns nil if successful" do
      error = mock("error")
      error.stubs(:present?).returns(false)
      response = stub(:error => error)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewers_for_source).returns(response)

      error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(@org, 1, @user)
      assert_nil error_message
    end

    test "returns an error on a nil response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewers_for_source).returns(nil)

      error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(@org, 1, @user)
      assert_equal error_message, "An error has occurred while attempting to delete the bypass reviewers for this source."
    end

    test "returns an error on an error response" do
      error = mock("error")
      error.stubs(:present?).returns(true)
      error.stubs(:msg).returns("Internal Server Error")
      response = stub(:error => error)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewers_for_source).returns(response)

      error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(@org, 1, @user)
      assert_equal error_message, "Internal Server Error"
    end

    context "instrumentation" do
      test "emits event in audit log when bypass reviewers are removed from repo" do
        error = mock("error")
        error.stubs(:present?).returns(false)
        response = stub(:error => error)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewers_for_source).returns(response)

        GitHub.expects(:instrument).with(
          "repository_secret_scanning_push_protection_bypass_list.remove",
          {
            actor: @user,
            repo: @org_owned_repo,
            security_configuration_id: nil,
            bulk_update: true,
          }
        ).once

        error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(@org_owned_repo, nil, @user)
      end

      test "emits event in audit log when bypass reviewers are removed from org" do
        error = mock("error")
        error.stubs(:present?).returns(false)
        response = stub(:error => error)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:remove_bypass_reviewers_for_source).returns(response)

        GitHub.expects(:instrument).with(
          "org_secret_scanning_push_protection_bypass_list.remove",
          {
            actor: @user,
            org: @org,
            security_configuration_id: 1,
            bulk_update: true,
          }
        ).once

        error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(@org, 1, @user)
      end
    end
  end

  context "update_bypass_reviewers_for_source" do
    test "returns true on a successful request" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::UpdateBypassReviewersForSourceResponse.new)
      data.stubs(:bypass_reviewers).returns([@reviewer])
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:update_bypass_reviewers_for_source).returns(response)

      result, error_message = SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(@org, 1, [@reviewer], @user)
      refute_nil result
      refute_empty result
      assert_nil error_message
    end

    test "returns an error on a nil response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:update_bypass_reviewers_for_source).returns(nil)

      result, error_message = SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(@org, 1, [@reviewer], @user)
      assert_nil result
      assert_equal error_message, "An error has occurred while attempting to update the bypass reviewers."
    end

    test "returns an error on an error response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::UpdateBypassReviewersForSourceResponse.new)
      data.stubs(:bypass_reviewers).returns(nil)
      error = mock("error")
      error.stubs(:present?).returns(true)
      error.stubs(:msg).returns("Internal Server Error")
      response = stub(:data => data, :error => error)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:update_bypass_reviewers_for_source).returns(response)

      result, error_message = SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(@org, 1, [@reviewer], @user)
      assert_nil result
      assert_equal error_message, "Internal Server Error"
    end

    test "returns an error if empty response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::UpdateBypassReviewersForSourceResponse.new)
      data.stubs(:bypass_reviewers).returns(nil)
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:update_bypass_reviewers_for_source).returns(response)

      result, error_message = SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(@org, 1, [@reviewer], @user)
      assert_nil result
      assert_equal error_message, "Failed to update bypass reviewers."
    end

    context "instrumentation" do
      test "emits event in audit log when bypass reviewers are updated for repo" do
        data = mock("data")
        data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::UpdateBypassReviewersForSourceResponse.new)
        data.stubs(:bypass_reviewers).returns([@reviewer])
        response = stub(:data => data, :error => nil)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:update_bypass_reviewers_for_source).returns(response)

        GitHub.expects(:instrument).with(
          "repository_secret_scanning_push_protection_bypass_list.add",
          {
            actor: @user,
            security_configuration_id: nil,
            repo: @org_owned_repo,
            bypass_reviewers: [@reviewer],
            bulk_update: true,
          }
        ).once

        result, error_message = SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(@org_owned_repo, nil, [@reviewer], @user)
      end

      test "emits event in audit log when bypass reviewers are updated for org" do
        data = mock("data")
        data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::UpdateBypassReviewersForSourceResponse.new)
        data.stubs(:bypass_reviewers).returns([@reviewer])
        response = stub(:data => data, :error => nil)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:update_bypass_reviewers_for_source).returns(response)

        GitHub.expects(:instrument).with(
          "org_secret_scanning_push_protection_bypass_list.add",
          {
            actor: @user,
            security_configuration_id: 1,
            org: @org,
            bypass_reviewers: [@reviewer],
            bulk_update: true,
          }
        ).once

        result, error_message = SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(@org, 1, [@reviewer], @user)
      end
    end
  end

  context "get_bypass_reviewers" do
    test "returns bypass reviewers if successful" do
      data = mock("data")
      data.stubs(:bypass_reviewers).returns([GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(id: 1, owner_id: 1, owner_scope: :REPOSITORY_SCOPE, reviewer_id: 1, reviewer_type: :TEAM)])
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)

      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(@org_owned_repo, @user.id)
      refute_nil bypass_reviewers
      refute_empty bypass_reviewers
      assert_nil error_message
    end

    test "returns error on nil response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(nil)

      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(@org_owned_repo, @user.id)
      assert_nil bypass_reviewers
      assert_equal error_message, "An error has occurred while attempting to retrieve the bypass reviewers."
    end

    test "returns error on error response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse.new)
      data.stubs(:bypass_reviewers).returns(nil)
      error = stub("error")
      error.stubs(:present?).returns(true)
      error.stubs(:msg).returns("Internal Server Error")
      response = stub(:error => error, :data => data)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)

      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(@org_owned_repo, @user.id)
      assert_nil bypass_reviewers
      assert_equal error_message, "Internal Server Error"
    end

    test "returns error on empty response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse.new)
      data.stubs(:bypass_reviewers).returns(nil)
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)

      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(@org_owned_repo, @user.id)
      assert_nil bypass_reviewers
      assert_equal error_message, "Failed to retrieve bypass reviewers."
    end

    test "deduplicates bypass reviewers" do
      return_reviewers = [
        GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(id: 1, owner_id: 1, owner_scope: :REPOSITORY_SCOPE, reviewer_id: 1, reviewer_type: :TEAM),
        GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(id: 2, owner_id: 1, owner_scope: :REPOSITORY_SCOPE, reviewer_id: 1, reviewer_type: :TEAM),
        GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(id: 3, owner_id: 1, owner_scope: :REPOSITORY_SCOPE, reviewer_id: 1, reviewer_type: :TEAM),
        GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(id: 4, owner_id: 1, owner_scope: :REPOSITORY_SCOPE, reviewer_id: 2, reviewer_type: :TEAM),
        GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(id: 5, owner_id: 1, owner_scope: :REPOSITORY_SCOPE, reviewer_id: 1, reviewer_type: :ROLE),
      ]
      data = mock("data")
      data.stubs(:bypass_reviewers).returns(return_reviewers)
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)

      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(@org_owned_repo, @user.id)
      assert_nil error_message
      refute_nil bypass_reviewers
      refute_empty bypass_reviewers
      assert_equal 3, T.must(bypass_reviewers).length
      assert_equal 1, T.must(bypass_reviewers)[0]&.id
      assert_equal 4, T.must(bypass_reviewers)[1]&.id
      assert_equal 5, T.must(bypass_reviewers)[2]&.id
    end
  end

  context "get_bypass_reviewer_users_teams" do
    test "returns bypass reviewer users and teams if successful" do
      custom_repo_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
      user_role = create(:user_role, actor: @user, role: custom_repo_role, target: @org_owned_repo)
      data = mock("data")
      data.stubs(:bypass_reviewers).returns(
        [
          GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(
            id: 1,
            owner_id: @org_owned_repo.id,
            owner_scope: :REPOSITORY_SCOPE,
            reviewer_id: @team.id,
            reviewer_type: :TEAM
          ),
          GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(
            id: 2,
            owner_id: @org_owned_repo.id,
            owner_scope: :REPOSITORY_SCOPE,
            reviewer_id: custom_repo_role.id,
            reviewer_type: :ROLE
          ),
        ]
      )
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)

      users, teams, err = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewer_users_teams(@org_owned_repo, @user.id)

      refute_nil users
      refute_empty users
      refute_nil teams
      refute_empty teams
      assert_nil err

      assert_same_elements [@user], users
      assert_same_elements [@team], teams
    end

    test "returns error on nil response" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(nil)
      Failbot.expects(:report).once

      users, teams, err = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewer_users_teams(@org_owned_repo, @user.id)
      error = "An error has occurred while attempting to retrieve the bypass reviewers."
      assert_equal error, err
      assert_nil users
      assert_nil teams
    end

    test "returns error on error response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse.new)
      data.stubs(:bypass_reviewers).returns(nil)
      error = stub("error")
      error.stubs(:present?).returns(true)
      error.stubs(:msg).returns("Internal Server Error")
      response = stub(:error => error, :data => data)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)
      Failbot.expects(:report).once

      users, teams, err = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewer_users_teams(@org_owned_repo, @user.id)
      error = "Internal Server Error"
      assert_equal error, err
      assert_nil users
      assert_nil teams
    end

    test "returns error on empty response" do
      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse.new)
      data.stubs(:bypass_reviewers).returns(nil)
      response = stub(:data => data, :error => nil)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(response)
      Failbot.expects(:report).once

      users, teams, err = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewer_users_teams(@org_owned_repo, @user.id)
      error = "Failed to retrieve bypass reviewers."
      assert_equal error, err
      assert_nil users
      assert_nil teams
    end
  end

  context "can_review_bypass_request?" do
    test "returns true if the user has the repo delegated bypass FGP for the repo" do
      # The org admin should have this FGP for the repo
      result = Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :repo_review_and_manage_secret_scanning_bypass_requests,
        actor: @admin,
        subject: @org_owned_repo
      ).sync
      assert result.then(&:allow?)
      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, @admin)
    end

    test "returns true if the user has the org delegated bypass FGP for the repo" do
      # Create a user and grant it the org FGP via a custom role
      org_fgp_user = create(:user)
      @org.add_member(org_fgp_user)
      grant_custom_org_role(user: org_fgp_user, target: @org, fgps: [:org_review_and_manage_secret_scanning_bypass_requests])
      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, org_fgp_user)
    end

    test "returns false for invalid secret scanning bypass reviewers - user types" do
      reviewer_user = create(:user)
      another_user = create(:user)
      reviewers = [
        stub(reviewer_id: reviewer_user.id, reviewer_type: :USER),
        stub(reviewer_id: reviewer_user.id - 1, reviewer_type: :USER),
      ]
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil]).times(2)

      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, reviewer_user)
      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, another_user)
    end

    test "returns true/false for valid secret scanning bypass reviewers - team types" do
      reviewer_user = create(:user)
      another_user_1 = create(:user)
      team = @org.teams.create(name: "Allowed team", privacy: :closed)
      team.add_member(reviewer_user)
      team.add_member(another_user_1)
      team.save!

      another_team = @org.teams.create(name: "Another team", privacy: :closed)
      another_user_2 = create(:user)
      another_team.add_member(another_user_2)
      another_team.save!

      reviewers = [
        # Add a random user in for good measure
        stub(reviewer_id: reviewer_user.id + 1, reviewer_type: :USER),

        stub(reviewer_id: team.id, reviewer_type: :TEAM),
      ]

      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil]).times(3)

      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, reviewer_user)
      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, another_user_1)
      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, another_user_2)
    end

    test "returns true/false for valid secret scanning bypass reviewers - default role types" do
      maintainer = create(:user)
      @org_owned_repo.add_member(maintainer, action: :maintain)
      reader = create(:user)
      @org_owned_repo.add_member(reader, action: :read)
      writer = create(:user)
      @org_owned_repo.add_member(writer, action: :write)

      reviewers = [
        # Add a random user in for good measure
        stub(reviewer_id: writer.id + 1, reviewer_type: :USER),
        stub(reviewer_id: Role.internal_role_by_name("write")&.id, reviewer_type: :ROLE),
        stub(reviewer_id: Role.internal_role_by_name("maintain")&.id, reviewer_type: :ROLE),
      ]
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil]).times(3)

      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, maintainer)
      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, writer)
      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, reader)
    end

    test "returns true/false for valid secret scanning bypass reviewers - custom role types" do
      write_role = RepositoryRole.write_role
      custom_role = create(:custom_repository_role, name: "custom_role", owner_id: @org.id, owner_type: "Organization", base_role_id: write_role.id)

      user_role_through_team = create(:user)
      team = create(:team, organization: @org, privacy: :closed)
      team.add_member(user_role_through_team)
      team.add_repository(@org_owned_repo, custom_role.name)

      user_role_through_user = create(:user)
      @org_owned_repo.add_member(user_role_through_user, action: custom_role.name)
      user_other = create(:user)
      @org_owned_repo.add_member(user_other, action: :write)

      reviewers = [
        stub(reviewer_id: custom_role.id, reviewer_type: :ROLE),
      ]
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil]).times(3)

      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, user_role_through_team)
      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, user_role_through_user)
      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, user_other)
    end

    test "returns true/false for valid secret scanning bypass reviewers - org admin types" do
      # Currently, repo rules hardcodes the reviewer ID for org admin types. The ID isn't actually used.
      reviewers = [
        stub(reviewer_id: 1, reviewer_type: :ORG_ADMIN),
      ]
      # We only call get_bypass_reviewers for users that don't have the FGP. Org admins have the FGP by default.
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil]).times(1)

      org_admin = @org_owned_repo.owner.admins[0]
      assert org_admin
      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, org_admin)
      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, @user)
    end

    test "returns true for other types if org admin is present but user is not an org admin" do
      reviewer_user = create(:user)
      team = @org.teams.create(name: "Allowed team", privacy: :closed)
      team.add_member(reviewer_user)
      team.save!

      reviewers = [
        stub(reviewer_id: 1, reviewer_type: :ORG_ADMIN),
        stub(reviewer_id: team.id, reviewer_type: :TEAM),
      ]

      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([reviewers, nil])

      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, reviewer_user)
    end

    test "returns false if TSS endpoint errors" do
      reviewer_user = create(:user)
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([nil, "Error"])
      refute SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, reviewer_user)
    end

    test "org enabled repository fetches org reviewers" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled_by_organization?).returns(true)
      reviewer_user = create(:user)
      team = @org.teams.create(name: "Allowed team", privacy: :closed)
      team.add_member(reviewer_user)
      team.save!

      reviewers = [stub(reviewer_id: team.id, reviewer_type: :TEAM),]

      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers)
        .with(@org_owned_repo, reviewer_user.id)
        .returns([reviewers, nil])
        .once

      assert SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(@org_owned_repo, reviewer_user)
    end
  end

  context "is_valid_reviewer?" do
    test "checks team validity" do
      assert SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(@team.id, "TEAM", @org)
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(@team.id + 1, "TEAM", @org)
      other_org = create(:organization)
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(@team.id, "TEAM", other_org)
    end

    test "checks default role validity - only allows repo admins and maintainers" do
      write_role = Role.write_role
      writer = create(:user)
      @org_owned_repo.add_member(writer, action: :write)
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(T.must(write_role.id), "ROLE", @org)
      invalid_role_id = Role.last.id + 1
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(invalid_role_id, "ROLE", @org)

      # The maintain default role is allowed
      maintain_role = RepositoryRole.maintain_role
      assert SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(T.must(maintain_role.id), "ROLE", @org)

      # The repo admin default role is allowed
      repo_admin_role = RepositoryRole.admin_role
      assert SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(T.must(repo_admin_role.id), "ROLE", @org)
    end

    test "checks custom role validity" do
      write_role = RepositoryRole.write_role
      custom_role = create(:custom_repository_role, name: "custom_role", owner_id: @org.id, owner_type: "Organization", base_role_id: write_role.id)
      other_org = create(:business_plus_organization)
      assert SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(custom_role.id, "ROLE", @org)
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(custom_role.id, "ROLE", other_org)
      other_org_custom_role = create(:custom_repository_role, name: "custom_role", owner_id: other_org.id, owner_type: "Organization", base_role_id: write_role.id)
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(other_org_custom_role.id, "ROLE", @org)
    end

    test "checks org admin validity" do
      assert SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(1, "ORG_ADMIN", @org)
      # Right now, the org admin role is hardcoded in the component with a default ID = 1.
      refute SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(2, "ORG_ADMIN", @org)
    end
  end

  context "suggested_bypass_reviewers" do
    test "includes repo admins, maintainers, custom roles, and teams" do
      # Create a custom role
      custom_role = create(:custom_repository_role, name: "My custom role", owner_id: @org.id, owner_type: "Organization")
      repo_admin_role = RepositoryRole.admin_role
      maintain_role = RepositoryRole.maintain_role
      expected_bypass_reviewers = [
        { actorId: repo_admin_role.id, actorType: :RepositoryRole, name: "Repository admin", preferred_avatar_url: nil, owner: nil },
        { actorId: maintain_role.id, actorType: :RepositoryRole, name: "Maintain", preferred_avatar_url: nil, owner: nil },
        { actorId: custom_role.id, actorType: :RepositoryRole, name: custom_role.name, preferred_avatar_url: nil, owner: nil },
        { actorId: @team.id, actorType: :Team, name: @team.name, preferred_avatar_url: @team.primary_avatar_url(20), owner: nil }]
      # Note that we do care about the order in which these are returned
      assert_equal expected_bypass_reviewers, SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(@org_owned_repo, @user, ActionController::Parameters.new)
    end

    test "excludes default repo roles except for repo admin and maintainer" do
      bypass_actors = SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(@org_owned_repo, @user, ActionController::Parameters.new)
      roles = bypass_actors.filter { |bypass_actor| bypass_actor[:actorType] == :RepositoryRole }

      assert_equal roles.size, 2
      role_names = roles.map { |role| role[:name] }

      assert_includes role_names, "Repository admin"
      assert_includes role_names, "Maintain"
      refute_includes role_names, "Write"
      refute_includes role_names, "Read"
      refute_includes role_names, "Triage"
    end

    test "excludes integrations" do
      integration = create(:integration, default_permissions: { "contents" => :write, "administration" => :write })
      installation = make_integration_installation(integration: integration, repository: @org_owned_repo)
      integration_reviewer = { :actorId => integration.id, :actorType => :Integration, :name => integration.name, :preferred_avatar_url => integration.preferred_avatar_url, :owner => nil }
      refute_includes SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(@org_owned_repo, @user, ActionController::Parameters.new), integration_reviewer
    end

    test "excludes deploy keys" do
      key = create(:public_key, repository: @org_owned_repo)
      deploy_key = { :actorId => nil, :actorType => :DeployKey, :name => RepositoryRulesetBypassActor::DeployKey.name, :preferred_avatar_url => nil, :owner => nil }
      refute_includes SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(@org_owned_repo, @user, ActionController::Parameters.new), deploy_key
    end
  end

  context "use_delegated_bypass_flow" do
    test "false if public key" do
      actor = create(:public_key, repository: @org_owned_repo)
      refute SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@org_owned_repo, actor)
    end

    test "false if delegated bypass is disabled" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled?).returns(false)
      refute SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@org_owned_repo, @user)
    end

    test "false if the user can review their own push" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).returns(true)
      refute SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@org_owned_repo, @user)
    end

    test "true if get_bypass_reviewers errors" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).returns(false)
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([[], SecretScanning::Errors::Error.new("error")])

      assert SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@org_owned_repo, @user)
    end

    test "false if reviewer list is empty" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).returns(false)
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([[], nil])
      refute SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@org_owned_repo, @user)
    end

    test "true if happy path" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).returns(false)
      SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers).returns([[@team], nil])
      assert SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@org_owned_repo, @user)
    end
  end
end
