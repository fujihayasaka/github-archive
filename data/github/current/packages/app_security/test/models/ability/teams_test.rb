# typed: true
# frozen_string_literal: true

require "test_helper"

class AbilitiesRelatedToTeamsTest < GitHub::TestCase
  fixtures do
    @org   = create(:organization)
    @repo  = create :repository, :minimal, owner: @org
    @team  = create :team, organization: @org, permission: "pull", privacy: :closed
    @secret_team = create :team, organization: @org, privacy: :secret
    @user  = create(:user)
  end

  test "members of an organization can read all non-secret teams" do
    @org.add_member @user

    assert_able @user, :read, @team
    refute_able @user, :write, @team

    refute_able @user, :read, @secret_team
  end

  test "teams added to an organization inherit the org's admin actors" do
    @org.add_member @user, action: :admin
    new_team = create :team, organization: @org

    assert_able @user, :admin, new_team
    ability = Authorization.service.most_capable_ability_between(actor: @user, subject: new_team)
    assert ability.admin?
  end

  test "ancestry is correctly calculated for org admins on new teams" do
    @org.add_member @user, action: :admin
    new_team = create :team, organization: @org

    org_admin  = Authorization.service.most_capable_ability_between(actor: @user, subject: @org)
    team_admin = Authorization.service.most_capable_ability_between(actor: @user, subject: new_team)
    assert_equal org_admin.id, team_admin.parent_id
  end

  test "membership and repository abilities are destroyed when the team is destroyed" do
    team = create :team, organization: @org

    # Add a user to the team
    @org.add_member(@user)
    @team.add_member(@user)

    # Add a repo to the team
    @team.add_repository(@repo, :push)

    refute_nil Authorization.service.most_capable_ability_between(actor: @user, subject: @team)
    refute_nil Authorization.service.most_capable_ability_between(actor: @team, subject: @repo)

    perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
      @team.destroy
    end

    # Both abilities should be destroyed
    assert_nil Authorization.service.most_capable_ability_between(actor: @user, subject: @team)
    assert_nil Authorization.service.most_capable_ability_between(actor: @team, subject: @repo)
  end
end
