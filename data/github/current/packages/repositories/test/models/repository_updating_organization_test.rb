# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryUpdatingOrganizationTest < GitHub::TestCase
  setup do
    @org = create(:organization, plan: "silver")
    @private_repo = create(:private_repository, owner: @org)
    @team = create(:team, organization: @org)
    @team.add_repository @private_repo, :pull

    @new_org = create(:organization, plan: "silver")
    @new_org_team = create :team, organization: @new_org
    @new_org_team.add_repository(@private_repo, :pull, allow_different_owner: true)

    @private_repo.update!(owner: @new_org)

    @private_repo.update_organization
  end

  test "removes old owner's teams" do
    refute @private_repo.teams.include? @team
  end

  test "does not remove new owner teams" do
    assert @private_repo.teams.include? @new_org_team
  end

  test "removes direct collaborators" do
    @private_repo.add_member create(:user)
    assert_equal 1, @private_repo.members.size

    @private_repo.update!(owner: @org)
    @private_repo.update_organization

    assert_equal 0, @private_repo.members.size
  end
end
