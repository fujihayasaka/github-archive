# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProduct
  class AuthorizationEnumeratorTest < GitHub::TestCase
    include DuplicateQueryTestHelper
    include FineGrainedPermissionsTestHelper

    context "#for_dependabot" do
      test "creates instance with only view_dependabot FGP" do
        user = create(:user)
        target = AuthorizationEnumerator.for_dependabot(user)

        assert_instance_of AuthorizationEnumerator, target
        assert_equal [:view_dependabot_alerts], target.actions
      end
    end

    context "#initialize" do
      test "requires user" do
        test_values = [
          nil,
          42,
          "apple",
          Repository.first,
        ]
        test_values.each do |value|
          assert_raises ArgumentError, "Must provide a user" do
            target = AuthorizationEnumerator.new(user: value, actions: [])
          end
        end
      end

      test "requires array of action FGPs" do
        user = create(:user)

        test_values = [
          nil,
          42,
          "apple",
          Repository.first,
          [42],
          ["apple"],
          [Repository.first],
        ]
        test_values.each do |value|
          assert_raises ArgumentError, "Must provide an array of supported FGP symbols" do
            target = AuthorizationEnumerator.new(user: user, actions: value)
          end
        end
      end
    end

    test "returns no repos if no action specified" do
      user = create(:user)
      repo = create(:repository, owner: user)

      assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
        target = AuthorizationEnumerator.new(user: user, actions: [])
        assert_empty target.authorized_repository_ids
        assert_empty target.authorized_repository_ids_by_action
      end
    end

    context "repository admin" do
      test "includes repos where user is admin" do
        user = create(:user)
        repo1 = create(:repository, owner: user)
        repo2 = create(:repository, owner: user)

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is an admin" do
        user = create(:user)
        repo1 = create(:repository, owner: user)
        repo2 = create(:repository, owner: user)

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user is admin with multiple fgps" do
        user = create(:user)
        repo1 = create(:repository, owner: user)
        repo2 = create(:repository, owner: user)

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts, :read_code_scanning])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts, :read_code_scanning], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:read_code_scanning]
        end
      end

      test "does not include repos outside the provided scope where user is an admin with multiple fgps" do
        user = create(:user)
        repo1 = create(:repository, owner: user)
        repo2 = create(:repository, owner: user)

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts, :read_code_scanning], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts, :read_code_scanning], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:read_code_scanning]
        end
      end

      test "includes repos where user is on a team with admin" do
        user = create(:user)
        org = create(:organization)
        org.add_member(user)
        team = create(:public_team, organization: org)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          team.add_repository(repo, :admin)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a team with admin" do
        user = create(:user)
        org = create(:organization)
        org.add_member(user)
        team = create(:public_team, organization: org)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          team.add_repository(repo, :admin)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user is on a child team of a team with admin" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:public_team, organization: org)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          repo.add_team(grandparent_team, action: :admin)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a child team of a team with admin" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:public_team, organization: org)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          repo.add_team(grandparent_team, action: :admin)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end
    end

    context "repository 'access to alerts'" do
      test "includes repos where user has 'access to alerts'" do
        user = create(:user)
        [
          repo1 = create(:repository),
          repo2 = create(:repository),
        ].each do |repo|
          repo.vulnerability_manager.add_authorized_user_or_team(user)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope includes repos where user has 'access to alerts'" do
        user = create(:user)
        [
          repo1 = create(:repository),
          repo2 = create(:repository),
        ].each do |repo|
          repo.vulnerability_manager.add_authorized_user_or_team(user)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user is on a team with 'access to alerts'" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:public_team, organization: org)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          repo.add_team(grandparent_team, action: :read)
          repo.vulnerability_manager.add_authorized_user_or_team(grandparent_team)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a team with 'access to alerts'" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:public_team, organization: org)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          repo.add_team(grandparent_team, action: :read)
          repo.vulnerability_manager.add_authorized_user_or_team(grandparent_team)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end
    end

    context "organization owner" do
      test "includes repos where user is an org owner" do
        user = create(:user)
        org = create(:organization, admin: user)
        repo1 = create(:repository, owner: org)
        repo2 = create(:repository, owner: org)

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is an org owner" do
        user = create(:user)
        org = create(:organization, admin: user)
        repo1 = create(:repository, owner: org)
        repo2 = create(:repository, owner: org)

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end
    end

    context "organization security manager" do
      test "includes repos where user is on a security manager team" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        team = create(:security_manager_team, organization: org, privacy: :closed)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          team.add_repository(repo, :read)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a security manager team" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        team = create(:security_manager_team, organization: org, privacy: :closed)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          team.add_repository(repo, :read)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user is on a child team of a security manager team" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:security_manager_team, organization: org, privacy: :closed)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          repo.add_team(grandparent_team, action: :read)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a child team of a security manager team" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:security_manager_team, organization: org, privacy: :closed)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          repo.add_team(grandparent_team, action: :read)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos where user is on a security manager team if include_security_manager_check is false" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        team = create(:security_manager_team, organization: org, privacy: :closed)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          team.add_repository(repo, :read)
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { include_security_manager_check: false }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_empty target.authorized_repository_ids
          assert_empty target.authorized_repository_ids_by_action.keys
        end
      end
    end

    context "fine grained permissions" do
      test "includes repos where user has specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: user, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user has specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: user, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user is on a team that has specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        team = create(:public_team, organization: org)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: team, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a team that has specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        team = create(:public_team, organization: org)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: team, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user is on a child team of a team that has specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:public_team, organization: org)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: grandparent_team, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts])
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user is on a child team of a team that has specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)
        org.add_member(user)

        grandparent_team = create(:public_team, organization: org)
        parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
        team = create(:public_team, organization: org, parent_team_id: parent_team.id)
        team.add_member(user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: grandparent_team, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: [:view_dependabot_alerts], options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user has one of specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: user, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "does not include repos outside the provided scope where user has one of specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: user, target: repo, fgps: [:view_dependabot_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS, options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
        end
      end

      test "includes repos where user has multiple of specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: user, target: repo, fgps: [:view_dependabot_alerts, :view_secret_scanning_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts, :view_secret_scanning_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
          assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:view_secret_scanning_alerts]
        end
      end

      test "does not include repos outside the provided scope where user has multiple of specified fgp" do
        org = create(:business_plus_organization)
        user = create(:user)

        [
          repo1 = create(:repository, owner: org),
          repo2 = create(:repository, owner: org),
        ].each do |repo|
          grant_custom_role(user: user, target: repo, fgps: [:view_dependabot_alerts, :view_secret_scanning_alerts])
        end

        assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
          options = { organization: org, repository_ids: [repo1.id] }
          target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS, options: options)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:view_dependabot_alerts, :view_secret_scanning_alerts], target.authorized_repository_ids_by_action.keys
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_dependabot_alerts]
          assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:view_secret_scanning_alerts]
        end
      end
    end

    context "implicit fine grained permissions from system roles" do
      test "includes repos from an organization that has set a base role of 'admin' for the implicit fgps granted by that role" do
        user = create(:user)

        # By default, the base repository role is "read". So we need to set it to the system role under test
        org_with_base = create(:business_plus_organization)
        org_with_base.config.set(Configurable::DefaultRepositoryPermission::KEY, :admin, org_with_base.admins.first)
        org_with_base.add_member(user)

        org_without_base = create(:business_plus_organization)
        org_without_base.config.set(Configurable::DefaultRepositoryPermission::KEY, :none, org_without_base.admins.first)
        org_without_base.add_member(user)

        repo1 = create(:repository, owner: org_with_base)
        repo2 = create(:repository, owner: org_without_base)

        # 2 for fetching the security manager teams for each org
        assert_duplicate_query_detection(AuthorizationEnumerator, 2) do
          target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
          assert_same_elements [repo1.id], target.authorized_repository_ids
          assert_same_elements [:read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts], target.authorized_repository_ids_by_action.keys
          target.authorized_repository_ids_by_action.keys.each do |action|
            assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[action]
          end
        end
      end

      # :maintain is an internal role that grants the :write ability as well as a separate user_role record with associated role_permissions FGPs
      [:write, :maintain].each do |system_role|
        test "includes repos where user has '#{system_role}' role with implicit fgp" do
          org = create(:business_plus_organization)
          user = create(:user)

          [
            repo1 = create(:repository, owner: org),
            repo2 = create(:repository, owner: org),
          ].each do |repo|
            repo.add_member(user, action: system_role)
          end

          assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
            assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:read_code_scanning]
          end
        end

        test "does not include repos outside the provided scope where user has '#{system_role}' role with implicit fgp" do
          org = create(:business_plus_organization)
          user = create(:user)

          [
            repo1 = create(:repository, owner: org),
            repo2 = create(:repository, owner: org),
          ].each do |repo|
            repo.add_member(user, action: system_role)
          end

          assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
            options = { organization: org, repository_ids: [repo1.id] }
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS, options: options)
            assert_same_elements [repo1.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:read_code_scanning]
          end
        end

        test "includes repos where user is on a team that has '#{system_role}' role with implicit fgp" do
          org = create(:business_plus_organization)
          user = create(:user)
          org.add_member(user)

          team = create(:public_team, organization: org)
          team.add_member(user)

          [
            repo1 = create(:repository, owner: org),
            repo2 = create(:repository, owner: org),
          ].each do |repo|
            team.add_repository(repo, system_role)
          end

          assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
            assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:read_code_scanning]
          end
        end

        test "does not include repos outside the provided scope where user is on a team that has '#{system_role}' role with implicit fgp" do
          org = create(:business_plus_organization)
          user = create(:user)
          org.add_member(user)

          team = create(:public_team, organization: org)
          team.add_member(user)

          [
            repo1 = create(:repository, owner: org),
            repo2 = create(:repository, owner: org),
          ].each do |repo|
            team.add_repository(repo, system_role)
          end

          assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
            options = { organization: org, repository_ids: [repo1.id] }
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS, options: options)
            assert_same_elements [repo1.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:read_code_scanning]
          end
        end

        test "includes repos where user is on a child team of a team that has '#{system_role}' role with implicit fgp" do
          org = create(:business_plus_organization)
          user = create(:user)
          org.add_member(user)

          grandparent_team = create(:public_team, organization: org)
          parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
          team = create(:public_team, organization: org, parent_team_id: parent_team.id)
          team.add_member(user)

          [
            repo1 = create(:repository, owner: org),
            repo2 = create(:repository, owner: org),
          ].each do |repo|
            repo.add_team(grandparent_team, action: system_role)
          end

          assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
            assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            assert_same_elements [repo1.id, repo2.id], target.authorized_repository_ids_by_action[:read_code_scanning]
          end
        end

        test "does not include repos outside the provided scope where user is on a child team of a team that has '#{system_role}' role with implicit fgp" do
          org = create(:business_plus_organization)
          user = create(:user)
          org.add_member(user)

          grandparent_team = create(:public_team, organization: org)
          parent_team = create(:public_team, organization: org, parent_team_id: grandparent_team.id)
          team = create(:public_team, organization: org, parent_team_id: parent_team.id)
          team.add_member(user)

          [
            repo1 = create(:repository, owner: org),
            repo2 = create(:repository, owner: org),
          ].each do |repo|
            repo.add_team(grandparent_team, action: system_role)
          end

          assert_duplicate_query_detection(AuthorizationEnumerator, 0) do
            options = { organization: org, repository_ids: [repo1.id] }
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS, options: options)
            assert_same_elements [repo1.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[:read_code_scanning]
          end
        end

        test "includes repos from an organization that has set a base role of '#{system_role}' for the implicit fgps granted by that role" do
          user = create(:user)

          # By default, the base repository role is "read". So we need to set it to the system role under test
          org_with_base = create(:business_plus_organization)
          org_with_base.config.set(Configurable::DefaultRepositoryPermission::KEY, system_role, org_with_base.admins.first)
          org_with_base.add_member(user)

          org_without_base = create(:business_plus_organization)
          org_without_base.config.set(Configurable::DefaultRepositoryPermission::KEY, :none, org_without_base.admins.first)
          org_without_base.add_member(user)

          repo1 = create(:repository, owner: org_with_base)
          repo2 = create(:repository, owner: org_without_base)

          # 2 for fetching the security manager teams for each org
          assert_duplicate_query_detection(AuthorizationEnumerator, 2) do
            target = AuthorizationEnumerator.new(user: user, actions: AuthorizationEnumerator::SUPPORTED_ACTIONS)
            assert_same_elements [repo1.id], target.authorized_repository_ids
            assert_same_elements [:read_code_scanning, :view_dependabot_alerts], target.authorized_repository_ids_by_action.keys
            target.authorized_repository_ids_by_action.keys.each do |action|
              assert_same_elements [repo1.id], target.authorized_repository_ids_by_action[action]
            end
          end
        end
      end
    end
  end
end
