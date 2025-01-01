# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueAbilityDependencyTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:verified_user)
    @viewer = create(:verified_user)
    @business = create(:business)
    @org = create_org_with_none_as_default_repository_permission
  end

  def create_org_with_none_as_default_repository_permission
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      create(:organization, admin: @org_admin, business: @business).tap do |org|
        org.update_default_repository_permission(:none, actor: @org_admin)
      end
    end
  end

  context ".visible_ids_for" do
    test "raises when provided with a non-authorizable" do
      assert_raises_with_message(ArgumentError, "expected Issue::Authorizable but found Issue") do |_e|
        Issue.visible_ids_for(viewer: @viewer, authorizables: [Issue.new])
      end
    end

    test "returns issue ids for public repos even with an anonymous user" do
      public_issue = create(:issue)
      private_issue = create(:issue, repository: create(:private_repository))

      assert_same_elements(
        [public_issue.id],
        Issue.visible_ids_for(
          viewer: nil,
          authorizables: [public_issue,  private_issue].map(&:to_issue_authorizable)
        )
      )
    end

    test "returns issue ids from only those private repositories that the user can access" do
      user_issue_with_access = create(
        :issue,
        repository: create(:private_repository).tap { |r| r.add_member(@viewer) }
      )
      org_issue_with_access = create(
        :issue,
        repository: create(:private_repository, owner: @org).tap { |r| r.add_member(@viewer) }
      )
      user_issue_without_access = create(:issue, repository: create(:private_repository))
      org_issue_without_access = create(:issue, repository: create(:private_repository, owner: @org))

      assert_same_elements(
        [user_issue_with_access.id, org_issue_with_access.id],
        Issue.visible_ids_for(
          viewer: @viewer,
          authorizables: [
            user_issue_with_access,
            org_issue_with_access,
            user_issue_without_access,
            org_issue_without_access,
          ].map(&:to_issue_authorizable)
        )
      )
    end

    test "does not return issue ids from internal repos if user does not have access" do
      not_visible_internal_issue = create(:issue, repository: create(:internal_repository, owner: @org))

      refute @viewer.organization_ids.include?(@org.id)
      refute @viewer.associated_repository_ids.include?(not_visible_internal_issue.repository_id)

      assert_same_elements(
        [],
        Issue.visible_ids_for(
          viewer: @viewer,
          authorizables: [not_visible_internal_issue].map(&:to_issue_authorizable)
        )
      )
    end

    test "returns issue ids from non-public repos that have been unlocked for the viewer" do
      viewer = create(:staff_admin_user)

      unlocked_private_issue = create(
        :issue,
        repository: create(:private_repository).tap { |repo| admin_unlock_repo(viewer, repo) }
      )
      unlocked_internal_issue = create(
        :issue,
        repository: create(:internal_repository).tap { |repo| admin_unlock_repo(viewer, repo) }
      )

      ordinary_private_issue = create(:issue, repository: create(:private_repository))
      ordinary_internal_issue = create(:issue, repository: create(:internal_repository))

      # In dotcom, private/internal issues should not be returned as they are not unlocked for the viewer.
      # However, in enterprise, internal issues are visible by default for org members.
      expected = if GitHub.enterprise?
        [unlocked_private_issue.id, unlocked_internal_issue.id, ordinary_internal_issue.id]
      else
        [unlocked_private_issue.id, unlocked_internal_issue.id]
      end

      assert_same_elements(
        expected,
        Issue.visible_ids_for(
          viewer: viewer,
          authorizables: [
            unlocked_private_issue,
            ordinary_private_issue,
            unlocked_internal_issue,
            ordinary_internal_issue
          ].map(&:to_issue_authorizable)
        )
      )
    end

    test "returns issue ids from internal repos and "\
      "internal repos that the user can access via org membership" do
      @org.add_member(@viewer)

      other_org = create_org_with_none_as_default_repository_permission
      assert_equal @org.business, other_org.business

      non_member_org_internal_issue = create(:issue, repository: create(:internal_repository, owner: other_org))
      inaccessible_private_issue = create(:issue, repository: create(:private_repository, owner: @org))
      member_org_internal_issue = create(:issue, repository: create(:internal_repository, owner: @org))

      # This issue should be accessible despite the viewer not having a direct association
      # with the repository.
      refute @viewer.associated_repository_ids.include?(member_org_internal_issue.repository_id)

      assert_same_elements(
        [member_org_internal_issue.id, non_member_org_internal_issue.id],
        Issue.visible_ids_for(
          viewer: @viewer,
          authorizables: [
            member_org_internal_issue,
            non_member_org_internal_issue,
            inaccessible_private_issue,
          ].map(&:to_issue_authorizable)
        )
      )
    end

    test "returns issue ids from internal repos that the user can access via collaboratorship" do
      @org.outside_collaborator_ids << @viewer.id
      accessible_internal_repository = create(:internal_repository, owner: @org)
      accessible_internal_repository.add_member(@viewer)
      accessible_internal_issue = create(:issue, repository: accessible_internal_repository)

      inaccessible_repository = create(:private_repository, owner: @org)
      inaccessible_issue = create(:issue, repository: inaccessible_repository)

      assert @viewer.associated_repository_ids.include?(accessible_internal_issue.repository_id)
      refute @viewer.associated_repository_ids.include?(inaccessible_issue.repository_id)

      assert_same_elements(
        [accessible_internal_issue.id],
        Issue.visible_ids_for(
          viewer: @viewer,
          authorizables: [
            accessible_internal_issue,
            inaccessible_issue,
          ].map(&:to_issue_authorizable)
        )
      )
    end

    test "guest collaborators cannot access internal repos in orgs that they do not belong to", skip_enterprise: true do
      emu_owner = create :emu, :owner
      business = emu_owner.enterprise_managed_business

      org = create :organization, business: business, admin: emu_owner
      org2 = create :organization, business: business, admin: emu_owner

      guest_collaborator = create :emu, :guest_collaborator, business: business

      org_internal_repo = create(:internal_repository, owner: org)
      org2_internal_repo = create(:internal_repository, owner: org2)

      org.add_member(guest_collaborator)

      assert org.member?(guest_collaborator)
      refute org2.member?(guest_collaborator)

      accessible_issue = create(:issue, repository: org_internal_repo)
      inaccessible_issue = create(:issue, repository: org2_internal_repo)

      assert_same_elements(
        [accessible_issue.id],
        Issue.visible_ids_for(
          viewer: guest_collaborator,
          authorizables: [
            accessible_issue,
            inaccessible_issue,
          ].map(&:to_issue_authorizable)
        )
      )
    end
  end

  context ".legacy_visible_for" do
    test "returns a scope that will find only issues based on the given issue ids which the user can see" do
      viewer = create(:user, login: "viewer")

      org = create(:organization, plan: "bronze")
      org.update_default_repository_permission(:none, actor: org.admins.first)
      org.add_member(viewer)

      default_repo_permission_org = create(:organization,
        login: "default-repo-permission-org",
        plan: "bronze",
      )
      default_repo_permission_org.add_member(viewer)

      owned_org = create(:organization,
        login: "owned-org",
        admin: viewer,
        plan: "bronze",
      )

      public_issue = create(:issue)

      user_repo_with_access  = create(:private_repository)
      user_issue_with_access = create(:issue, repository: user_repo_with_access)
      user_repo_with_access.add_member(viewer)

      user_repo_without_access  = create(:private_repository)
      user_issue_without_access = create(:issue, repository: user_repo_without_access)

      org_repo_with_collab_access  = create(:private_repository, owner: org)
      org_issue_with_collab_access = create(:issue, repository: org_repo_with_collab_access)
      org_repo_with_collab_access.add_member(viewer)

      org_repo_with_team_access  = create(:private_repository, owner: org)
      org_issue_with_team_access = create(:issue, repository: org_repo_with_team_access)
      team                       = create(:team, organization: org)
      team.add_member(viewer)
      team.add_repository(org_repo_with_team_access, :pull)

      org_repo_with_owner_access  = create(:private_repository, owner: owned_org)
      org_issue_with_owner_access = create(:issue, repository: org_repo_with_owner_access)

      org_repo_with_default_repository_access  = create(:private_repository, owner: default_repo_permission_org)
      org_issue_with_default_repository_access = create(:issue, repository: org_repo_with_default_repository_access)

      org_repo_without_access  = create(:private_repository, owner: org)
      org_issue_without_access = create(:issue, repository: org_repo_without_access)

      expected_issues = [
        public_issue,
        user_issue_with_access,
        org_issue_with_collab_access,
        org_issue_with_team_access,
        org_issue_with_owner_access,
        org_issue_with_default_repository_access,
        # user_issue_without_access and org_issue_without_access shouldn't be returned
      ]

      assert_same_elements expected_issues, Issue.legacy_visible_for(Issue.ids, viewer: viewer)

      # Make sure we still return the correct scope when using the optimization option.
      assert_same_elements(
        expected_issues,
        Issue.legacy_visible_for(
          Issue.ids,
          viewer: viewer,
          issue_ids_by_private_repo_id: [
            user_issue_with_access,
            org_issue_with_collab_access,
            org_issue_with_team_access,
            org_issue_with_owner_access,
            org_issue_with_default_repository_access,
            user_issue_without_access,
            org_issue_without_access,
          ].group_by(&:repository_id).transform_values! { |issues| issues.map(&:id) }
        )
      )
    end

    test "only returns issues on public repositories when there's no viewer" do
      public_issue  = create(:issue)
      private_issue = create(:issue, repository: create(:private_repository))

      assert_same_elements [public_issue], Issue.legacy_visible_for(Issue.ids, viewer: nil)
    end
  end

  context ".legacy_visible_ids_for" do
    test "does not execute database queries when list of computed issue_ids_by_private_repo_id is provided but blank" do
      viewer = create(:user, login: "viewer")

      assert_no_queries do
        Issue.legacy_visible_ids_for(
          [1],
          viewer: viewer,
          issue_ids_by_private_repo_id: {},
        )
      end
    end
  end

  context "readable_by?" do
    test "is true when the user can read an issue's repository" do
      repo  = create(:repository)
      issue = create(:issue, repository: repo)

      assert issue.readable_by?(create(:user))
    end

    test "is false when the user cannot read an issue's repository" do
      repo  = create(:private_repository)
      issue = create(:issue, repository: repo)

      refute issue.readable_by?(create(:user))
    end

    test "is true when an installation has access to a repository's issues" do
      repo         = create(:private_repository)
      issue        = create(:issue, repository: repo)
      installation = make_integration_installation(
        repository: repo,
        permissions: { "issues" => :read },
      )

      assert issue.readable_by?(installation)
    end

    test "is false when an installation has access to a repository but not its issues" do
      repo         = create(:private_repository)
      issue        = create(:issue, repository: repo)
      installation = make_integration_installation(
        repository: repo,
        permissions: { "statuses" => :read },
      )

      refute issue.readable_by?(installation)
    end

    test "is false when the issue has no repository" do
      issue = build(:issue, repository: nil)
      refute issue.readable_by?(create(:user))
    end
  end

  context "user_ids_with_privileged_access" do
    test "returns owner, collaborators, and issue author for an issue on a user-owned public repo" do
      repo   = create(:repository)
      owner  = repo.owner
      collab = create(:user, login: "collab")
      repo.add_member(collab)

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      issue = create(:issue, repository: repo)

      assert_same_elements [owner, collab, issue.user].map(&:id), issue.user_ids_with_privileged_access
    end

    test "returns collaborators, team members, and issue author for an issue on an org-owned public repo" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_owner = org.admins.first
      repo      = create(:repository, owner: org)
      collab    = create(:user, login: "collab")
      repo.add_member(collab)

      team = create(:team, organization: org)
      team.add_repository(repo, :pull)

      team_member = create(:user, login: "team-member")
      org.add_member(team_member)
      team.add_member(team_member)

      org_member_without_privileged_access = create(:user, login: "org-member-without-privileged-access")
      org.add_member(org_member_without_privileged_access)

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      issue = create(:issue, repository: repo)

      assert_same_elements [org_owner, team_member, collab, issue.user].map(&:id), issue.user_ids_with_privileged_access
    end

    test "returns collaborators for an issue on an org-owned internal repo", skip_if_feature_disabled: :available_assignee_ids_with_repo_read_access do
      org_owner = @org.admins.first
      repo      = create(:internal_repository, owner: @org)
      collab    = create(:user, login: "collab")
      repo.add_member(collab)

      private_repo = create(:private_repository, owner: @org)
      private_repo_user = create(:user, login: "private-repo")
      private_repo.add_member(private_repo_user)

      team = create(:team, organization: @org)

      team_member = create(:user, login: "team-member")
      @org.add_member(team_member)
      team.add_member(team_member)

      org_member = create(:user, login: "org-member")
      @org.add_member(org_member)

      create(:user, login: "unaffiliated-user")

      issue = create(:issue, repository: repo)
      issue_private_repo = create(:issue, repository: private_repo)

      assert_same_elements [team_member, org_member, collab, org_owner].map(&:id), issue.user_ids_with_repo_read_access
      assert_same_elements [org_owner, private_repo_user].map(&:id), issue_private_repo.user_ids_with_repo_read_access
    end

    test "returns filtered list when request" do
      repo   = create(:repository)
      owner  = repo.owner
      collab = create(:user, login: "collab")
      repo.add_member(collab)

      unaffiliated_user = create(:user, login: "unaffiliated-user")

      issue = create(:issue, repository: repo)

      user_ids = [owner, issue.user].map(&:id)
      assert_same_elements user_ids, issue.user_ids_with_privileged_access(actor_ids_filter: user_ids)
    end
  end
end
