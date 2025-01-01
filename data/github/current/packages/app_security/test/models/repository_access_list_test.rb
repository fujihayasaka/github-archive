# typed: true
# frozen_string_literal: true

require "test_helper"

module RepositoryAccessListHelper
  def access_list_query(repository: @org_repo, current_user: @owner, query: nil, before: nil, after: nil, limit: nil)
    ::RepositoryAccessList.new(repository:, current_user:, query:, before:, after:, limit:)
  end
end

class RepositoryAccessListTest < GitHub::TestCase
  include RepositoryAccessListHelper
  include FineGrainedPermissionsTestHelper

  fixtures do
    @org = create :business_plus_organization
    @org_repo = create :private_repository, :minimal, owner: @org
    @owner = @org.admins.first
    @org_member = create :user, login: "org-member"
    @org.add_member(@org_member)
    @outside_collaborator = create :user, login: "collab-user"
    @team = create :team, organization: @org
    @user_repo = create :private_repository, :minimal, owner: @owner
    @custom_role = create_custom_role(role_name: "foo 👹 bar", owner: @org, base_role: :maintain, fgps: [:delete_issue])
  end

  context "query parsing" do
    test "extracts role from query" do
      query = access_list_query(query: "")
      assert_nil query.role

      query = access_list_query(query: "role:read")
      assert_equal :read, query.role

      query = access_list_query(query: "role:triage")
      assert_equal :triage, query.role

      query = access_list_query(query: "role:write")
      assert_equal :write, query.role

      query = access_list_query(query: "role:maintain")
      assert_equal :maintain, query.role

      query = access_list_query(query: "role:admin")
      assert_equal :admin, query.role

      # supports custom roles with spaces and emojis
      query = access_list_query(query: "role:'#{@custom_role.name}'")
      assert_equal @custom_role.name.to_sym, query.role

      # supports custom roles with internal role names
      query = access_list_query(query: "role:'#{Role::CODESPACES_SYSTEM_ROLES.first}'")
      assert_equal Role::CODESPACES_SYSTEM_ROLES.first.to_sym, query.role
    end

    test "detect query string when role is present" do
      query = access_list_query(query: "monalisa role:read")
      assert_equal "monalisa", query.query
      assert_equal :read, query.role

      query = access_list_query(query: "role:admin hubot the friendly robot")
      assert_equal "hubot the friendly robot", query.query
      assert_equal :admin, query.role

    end

    test "extracts filter from query for org owned repository" do
      query = access_list_query(query: "")
      assert_equal :all, query.filter

      query = access_list_query(query: "monalisa")
      assert_equal :all, query.filter

      query = access_list_query(query: "filter:org_members")
      assert_equal :org_members, query.filter

      query = access_list_query(query: "filter:outside_collaborators")
      assert_equal :outside_collaborators, query.filter

      query = access_list_query(query: "filter:teams")
      assert_equal :teams, query.filter

      query = access_list_query(query: "filter:pending_invitations")
      assert_equal :pending_invitations, query.filter
    end

    test "extracts filter from query for user owned repository" do
      query = access_list_query(repository: @user_repo, query: "hubot")
      assert_equal :all, query.filter

      query = access_list_query(repository: @user_repo, query: "filter:collaborators")
      assert_equal :collaborators, query.filter

      query = access_list_query(repository: @user_repo, query: "filter:pending_invitations")
      assert_equal :pending_invitations, query.filter
    end

    test "extracts both role and filter from query" do
      query = access_list_query(query: "monalisa role:read filter:teams")
      assert_equal "monalisa", query.query
      assert_equal :read, query.role
      assert_equal :teams, query.filter
    end
  end

  context "when parsing custom roles" do
    test "works with empty input" do
      query = access_list_query(query: "''")

      assert_nil query.role
    end

    test "extracts value from query" do
      query = access_list_query(query: "role:'a custom role name'")

      assert_equal :'a custom role name', query.role
    end

    test "extracts value with special chars from query" do
      role_with_special_chars = "!@#$%^&**(()=_=- 🤪"
      query = access_list_query(query: "role:'#{role_with_special_chars}'")

      assert_equal :"!@#$%^&**(()=_=- 🤪".to_sym, query.role
    end

    test "extracts value when query string present" do
      query = access_list_query(query: "monalisa role:'custom role'")

      assert_equal "monalisa", query.query
      assert_equal :'custom role', query.role
    end
  end

  context "direct_members" do
    test "doesn't show the organization owner" do
      query = access_list_query
      assert_empty query.results
    end

    test "shows a user with direct permissions" do
      @org_repo.add_member(@org_member)
      query = access_list_query
      assert_equal [@org_member], query.results
    end

    test "filters results based on a query" do
      @org_repo.add_member(@org_member)
      @org_repo.add_member(@outside_collaborator)

      query = access_list_query(query: @outside_collaborator.login)
      assert_equal [@outside_collaborator], query.results

      @org_member.update profile_name: "An org member"
      query = access_list_query(query: @org_member.profile_name)
      assert_equal [@org_member], query.results
    end

    test "filters results based on ability action" do
      another_user = create(:user)
      @org_repo.add_member(@org_member, action: :write)
      @org_repo.add_member(@outside_collaborator, action: :maintain)
      @org_repo.add_member(another_user, action: @custom_role.name.to_sym)
      query = access_list_query(query: "role:write")

      assert_equal [@org_member], query.results

      # run the test again, with a filter to exercise that path
      query = access_list_query(query: "role:write filter:org_members")
      assert_equal [@org_member], query.results
    end

    test "filters results based on role" do
      collab_admin = create :user
      @org_repo.add_member(@org_member, action: :triage)
      @org_repo.add_member(@outside_collaborator, action: :maintain)
      @org_repo.add_member(collab_admin, action: :admin)
      query = access_list_query(query: "role:triage")

      assert_equal [@org_member], query.results

      # run the test again, with a filter to exercise that path
      query = access_list_query(query: "filter:outside_collaborators role:maintain")
      assert_equal [@outside_collaborator], query.results

      # test the path where no UserRoles are filtered out
      query = access_list_query(query: "role:admin filter:outside_collaborators")
      assert_equal [collab_admin], query.results
    end

    test "filters results based on a custom role" do
      member = create(:user, login: "org-member-2")
      @org.add_member(member)
      collaborator = create(:user, login: "collab-user-2")

      @org_repo.add_member(@org_member, action: @custom_role.name)
      @org_repo.add_member(@outside_collaborator, action: @custom_role.name)
      @org_repo.add_member(member, action: @custom_role.base_role.name)
      @org_repo.add_member(collaborator, action: @custom_role.base_role.name)

      # run filter with a custom role
      query = access_list_query(query: "role:'#{@custom_role.name}'")
      assert_equal [@outside_collaborator, @org_member], query.results

      # run filter with a custom role and outside_collaborators
      query = access_list_query(query: "filter:outside_collaborators role:'#{@custom_role.name}'")
      assert_equal [@outside_collaborator], query.results

      # run filter with a custom role and outside_collaborators
      query = access_list_query(query: "filter:org_members role:'#{@custom_role.name}'")
      assert_equal [@org_member], query.results
    end

    test "ordering works across pages" do
      @org = create :organization
      @org_repo = create :private_repository, :minimal, owner: @org
      @owner = @org.admins.first

      1..50.times do |_|
        @org_repo.add_member(create(:user), action: :write)
      end

      assert_equal access_list_query(limit: 10).results.first.login, access_list_query(limit: 30).results.first.login

      query = access_list_query(limit: 10)
      assert_equal query.results.count, 10

      query = access_list_query(limit: 40, after: query.after_cursor)
      assert_equal query.results.count, 40
    end
  end

  context "repository_teams" do
    test "repository_teams shows teams with permissions on repository" do
      @team.add_repository(@org_repo, :pull)
      rando_team = create :team, organization: @org

      query = access_list_query

      assert_equal [@team], query.results
      refute_includes query.results, rando_team
    end

    test "filters results based on role" do
      @team.add_repository(@org_repo, :pull)
      custom_team = create :team, organization: @org
      custom_team.add_repository(@org_repo, @custom_role.name.to_sym)
      maintain_team = create :team, organization: @org
      maintain_team.add_repository(@org_repo, :maintain)
      admin_team = create :team, organization: @org
      admin_team.add_repository(@org_repo, :admin)

      query = access_list_query(query: "role:read")

      assert_equal [@team], query.results

      # Do the test again to exercise the FGP role path
      query = access_list_query(query: "role:maintain")
      assert_equal [maintain_team], query.results

      # Test the admin role
      query = access_list_query(query: "role:admin")
      assert_equal [admin_team], query.results
    end

    test "filters results based on a custom role" do
      team = create :team, organization: @org
      other_team = create :team, organization: @org

      team.add_repository(@org_repo, @custom_role.name)
      other_team.add_repository(@org_repo, @custom_role.base_role.name)

      # Ensure that all teams are returned
      query = access_list_query(query: "role:'#{@custom_role.name}'")
      assert_equal [team], query.results
    end

    test "filters results based on a custom role with internal role name" do
      custom_role = create(:custom_repository_role, name: Role::CODESPACES_SYSTEM_ROLES.first, owner_id: @org.id, owner_type: "Organization")
      team = create :team, organization: @org

      team.add_repository(@org_repo, custom_role.name)
      invitation = create :repository_invitation, repository: @org_repo, inviter: @owner, role: custom_role
      @org_repo.add_member(@outside_collaborator, action: custom_role.name.to_sym)

      # Ensure that all teams are returned
      query = access_list_query(query: "role:'#{custom_role.name}'")
      assert_equal [@outside_collaborator, team, invitation], query.results
    end

    test "filters results based on a query" do
      @team.add_repository(@org_repo, :pull)
      employee_team = create :team, organization: @org, name: "Employees"
      employee_team.add_repository(@org_repo, :push)

      query = access_list_query(query: employee_team.slug)

      assert_equal [employee_team], query.results

      # ensure search works for Team descriptions
      employee_team.update description: "A random team"
      query = access_list_query(query: employee_team.description)

      assert_equal [employee_team], query.results
    end

    test "ordering works across pages" do
      @org = create :organization
      @org_repo = create :private_repository, :minimal, owner: @org
      @owner = @org.admins.first

      1..50.times do |_|
        team = create :team, organization: @org
        team.add_repository(@org_repo, :push)
      end

      assert_equal access_list_query(limit: 10).results.first.slug, access_list_query(limit: 30).results.first.slug

      query = access_list_query(limit: 10)
      assert_equal query.results.count, 10

      query = access_list_query(limit: 40, after: query.after_cursor)
      assert_equal query.results.count, 40
    end
  end

  context "Repository Invitations" do
    test "invitations shows pending invitations to the repository" do
      repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write
      query = access_list_query

      assert_equal [repo_invite], query.results
    end

    test "does show expired invitations" do
      repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, created_at: DateTime.now - (GitHub.invitation_expiry_period + 1).days
      email_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: nil, email: "email@github.com", created_at: DateTime.now - (GitHub.invitation_expiry_period + 1).days
      assert repo_invite.invite_expired?
      assert email_invite.invite_expired?

      query = access_list_query

      assert_equal 2, query.results.length
    end

    test "invitations filters pending invitations by role" do
      repo_invite_1 = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write
      repo_invite_2 = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :read

      query = access_list_query(query: "role:read")

      assert_equal [repo_invite_2], query.results
    end

    test "invitations filters pending invitations by custom role" do
      repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, role: @custom_role

      query = access_list_query(query: "role:'#{@custom_role.name}'")

      assert_equal [repo_invite], query.results
    end

    test "filters results based on a query" do
      outside_collaborator_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: @outside_collaborator
      rando_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :read

      query = access_list_query(query: @outside_collaborator.login)
      assert_equal [outside_collaborator_invite], query.results

      @outside_collaborator.update profile_name: "not an org member"
      query = access_list_query(query: @outside_collaborator.profile_name)
      assert_equal [outside_collaborator_invite], query.results
    end

    test "user invites, ordering works across pages" do
      @org = create :organization
      @org_repo = create :private_repository, :minimal, owner: @org
      @owner = @org.admins.first

      1..50.times do |_|
        create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write
      end

      assert_equal access_list_query(limit: 10).results.first.invitee.login, access_list_query(limit: 30).results.first.invitee.login

      query = access_list_query(limit: 10)
      assert_equal query.results.count, 10

      query = access_list_query(limit: 40, after: query.after_cursor)
      assert_equal query.results.count, 40
    end

    test "email invites, ordering works across pages" do
      @org = create :organization
      @org_repo = create :private_repository, :minimal, owner: @org
      @owner = @org.admins.first

      1..50.times do |_i|
        create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: nil, email: "#{(0...10).map { ('a'..'z').to_a[rand(26)] }.join}@github.com", created_at: DateTime.now - (GitHub.invitation_expiry_period + 1).days
      end

      assert_equal access_list_query(limit: 10).results.first.email, access_list_query(limit: 30).results.first.email

      query = access_list_query(limit: 10)
      assert_equal query.results.count, 10

      query = access_list_query(limit: 40, after: query.after_cursor)
      assert_equal query.results.count, 40
    end
  end

  test "#before_cursor returns email if first result is an email invitation" do
    repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: nil, email: "email@github.com"
    query = access_list_query
    assert_equal repo_invite.email, query.before_cursor
  end

  test "#before_cursor returns invitee login if first result is a user invitation" do
    repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: @org_member
    query = access_list_query
    assert_equal repo_invite.invitee.login, query.before_cursor
  end

  test "#after_cursor returns email if last result is an email invitation" do
    repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: nil, email: "email@github.com"
    query = access_list_query
    assert_equal repo_invite.email, query.after_cursor
  end

  test "#after_cursor returns invitee login if last result is user invitation" do
    repo_invite = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: @org_member
    query = access_list_query
    assert_equal repo_invite.invitee.login, query.after_cursor
  end
end

class EditRepositoriesAccessQueryFiltersSortAndQueryResultLimitsTest < GitHub::TestCase
  include RepositoryAccessListHelper

  fixtures do
    @org = create :organization
    @org_repo = create :private_repository, :minimal, owner: @org
    @owner = @org.admins.first

    @org_member_a = create :user, login: "a-org-member"
    @org.add_member(@org_member_a)
    @org_repo.add_member(@org_member_a)
    @team_b = create :team, name: "b-team", organization: @org
    @team_b.add_repository @org_repo, :push
    @outside_collaborator_c = create :user, login: "c-outside-collaborator"
    @org_repo.add_member(@outside_collaborator_c)
    @invitee_d = create :user, login: "d-invitee"
    @invite_d = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: @invitee_d
    @team_e = create :team, name: "E-team", organization: @org
    @team_e.add_repository @org_repo, :pull
    @invitee_f = create :user, login: "F-invitee"
    @invite_f = create :repository_invitation, repository: @org_repo, inviter: @owner, permissions: :write, invitee: @invitee_f
    @org_member_g = create :user, login: "g-org-member"
    @org.add_member(@org_member_g)
    @org_repo.add_member(@org_member_g)
    @outside_collaborator_h = create :user, login: "H-outside-collaborator"
    @org_repo.add_member(@outside_collaborator_h)
  end

  test "#members without a filter shows all users" do
    query = access_list_query
    assert_same_elements query.direct_members, [@org_member_a, @outside_collaborator_c, @org_member_g, @outside_collaborator_h]
  end

  test "#teams shows all teams" do
    query = access_list_query
    assert_same_elements query.repository_teams, [@team_b, @team_e]
  end

  test "invitations shows all pending invitations" do
    query = access_list_query
    assert_same_elements query.invitations, [@invite_d, @invite_f]
  end

  test "filtering on org members only show selected types" do
    query = access_list_query(query: "filter:org_members")
    assert_equal [@org_member_a, @org_member_g], query.results
  end

  test "after pagination filtering on org members" do
    query = access_list_query(query: "filter:org_members", after: @org_member_a.login, limit: 1)
    assert_equal [@org_member_g], query.results
  end

  test "before pagination filtering on org members" do
    query = access_list_query(query: "filter:org_members", before: @org_member_g.login, limit: 1)
    assert_equal [@org_member_a], query.results
  end

  test "filtering on outside_collaborators only shows selected users" do
    query = access_list_query(query: "filter:outside_collaborators")
    assert_equal [@outside_collaborator_c, @outside_collaborator_h], query.results
  end

  test "after pagination filtering on outside collaborators" do
    query = access_list_query(query: "filter:outside_collaborators", after: @outside_collaborator_c.login, limit: 1)
    assert_equal [@outside_collaborator_h], query.results
  end

  test "before pagination filtering on outside collaborators" do
    query = access_list_query(query: "filter:outside_collaborators", before: @outside_collaborator_h.login, limit: 1)
    assert_equal [@outside_collaborator_c], query.results
  end

  test "filtering on teams only show selected types" do
    query = access_list_query(query: "filter:teams")
    assert_equal [@team_b, @team_e], query.results
  end

  test "after pagination filtering on teams" do
    query = access_list_query(query: "filter:teams", after: @team_b.slug, limit: 1)
    assert_equal [@team_e], query.results
  end

  test "before pagination filtering on teams" do
    query = access_list_query(query: "filter:teams", before: @team_e.slug, limit: 1)
    assert_equal [@team_b], query.results
  end

  test "filtering on pending_invitations only show selected types" do
    query = access_list_query(query: "filter:pending_invitations")
    assert_equal [@invite_d, @invite_f], query.results
  end

  test "after pagination filtering on pending invitations" do
    query = access_list_query(query: "filter:pending_invitations", after: @invitee_d.login, limit: 1)
    assert_equal [@invite_f], query.results
  end

  test "before pagination filtering on pending invitations" do
    query = access_list_query(query: "filter:pending_invitations", before: @invitee_f.login, limit: 1)
    assert_equal [@invite_d], query.results
  end

  test "#user_results returns no results when filter is :team or :pending_invitations" do
    invitation_query = access_list_query(query: "filter:pending_invitations")
    team_query = access_list_query(query: "filter:teams")
    assert_equal [], invitation_query.user_results
    assert_equal [], team_query.user_results
  end

  test "#user_results returns only user results without a filter" do
    expected = [@org_member_a, @org_member_g, @outside_collaborator_c, @outside_collaborator_h]

    assert_same_elements expected, access_list_query.user_results
  end

  test "#user_results returns only user results with :outside_collaborators filter" do
    expected = [@outside_collaborator_c, @outside_collaborator_h]

    assert_same_elements expected, access_list_query(query: "filter:outside_collaborators").user_results
  end

  test "#user_results returns only user results with :org_members filter" do
    expected = [@org_member_a, @org_member_g]

    assert_same_elements expected, access_list_query(query: "filter:org_members").user_results
  end

  test "filtering collaborators in user owned repo" do
    owner = create(:user, login: "owner")
    repo = create(:repository, :minimal, owner: owner)

    collab_a = create(:user, login: "a-collaborator")
    collab_b = create(:user, login: "b-collaborator")
    collab_c = create(:user, login: "c-collaborator")
    repo.add_member(collab_a)
    repo.add_member(collab_b)
    repo.add_member(collab_c)

    # other entries to ensure we only return filtered values
    invitee_d = create(:user, login: "d-collab-invitee")
    invite_d = create(:repository_invitation, repository: repo, inviter: owner, permissions: :write, invitee: invitee_d)

    query = access_list_query(repository: repo, query: "filter:collaborators")
    assert_equal [collab_a, collab_b, collab_c], query.results
  end

  test "results are sorted correctly" do
    query = access_list_query

    assert_equal [@org_member_a, @team_b, @outside_collaborator_c, @invite_d, @team_e, @invite_f, @org_member_g, @outside_collaborator_h], query.results
  end

  test "query returns limited number of sorted results" do
    query = access_list_query(limit: 2)

    assert_equal [@org_member_a, @team_b], query.results
  end

  test "query returns limited number of sorted results after an offset" do
    query = access_list_query(limit: 2, after: @team_b.slug)

    assert_equal [@outside_collaborator_c, @invite_d], query.results
  end

  test "query returns limited number of sorted results before an offset" do
    query = access_list_query(limit: 2, before: @invitee_f.login)

    assert_equal [@invite_d, @team_e], query.results
  end

  test "query returns sorted results starting from the beginning when paginating past the start" do
    query = access_list_query(limit: 4, before: @team_e.slug)

    assert_equal [@org_member_a, @team_b, @outside_collaborator_c, @invite_d], query.results
  end

  test "query returns sorted results ending at the end index when paginating past the end" do
    query = access_list_query(limit: 10, after: @invitee_d.login)

    assert_equal [@team_e, @invite_f, @org_member_g, @outside_collaborator_h], query.results
  end

  test "last page isn't detected when not at end" do
    query = access_list_query(limit: 2, after: @team_e.slug)

    assert_equal [@invite_f, @org_member_g], query.results
    refute query.end_of_results?
  end

  test "last page detection works exactly at end of query" do
    query = access_list_query(limit: 2, after: @invitee_f.login)

    assert_equal [@org_member_g, @outside_collaborator_h], query.results
    assert query.end_of_results?
  end

  test "last page detection works past the end of query" do
    query = access_list_query(limit: 2, after: @org_member_g.login)

    assert_equal [@outside_collaborator_h], query.results
    assert query.end_of_results?
  end

  test "first page is detected when no pagination parameters are supplied" do
    query = access_list_query(limit: 2)
    assert_equal [@org_member_a, @team_b], query.results
    assert query.start_of_results?
    refute query.end_of_results?
  end

  test "first page is detected paginating exactly to the beginning" do
    query = access_list_query(limit: 2, before: @outside_collaborator_c.login)
    assert_equal [@org_member_a, @team_b], query.results
    assert query.start_of_results?
    refute query.end_of_results?
  end

  test "first page is detected when paginating past the beginning" do
    query = access_list_query(limit: 2, before: @team_b.slug)
    assert_equal [@org_member_a], query.results
    assert query.start_of_results?
    refute query.end_of_results?
  end

  test "both first and last page are detected when entire result set is returned" do
    expected_results = [@org_member_a, @team_b, @outside_collaborator_c, @invite_d, @team_e, @invite_f, @org_member_g, @outside_collaborator_h]

    query = access_list_query(limit: expected_results.size)
    assert_equal expected_results, query.results
    assert query.start_of_results?
    assert query.end_of_results?
  end
end
