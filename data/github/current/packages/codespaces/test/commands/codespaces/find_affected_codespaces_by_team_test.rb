# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FindAffectedCodespacesByTeamTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @repository = create(:repository, owner: @organization)
    @org_member = create(:user, login: "org-member")
    @organization.add_member(@org_member, action: :admin)
    @team = create(:team, organization: @organization)
    @team.add_member(@org_member)
    @codespace = create(:codespace, repository: @repository, owner: @org_member)
    create(:codespace, repository: @repository, owner: @org_member)
  end

  context "#call" do
    test "loads multiple in relation" do
      expected = Codespace.where(owner: @org_member)
      assert_equal expected.count, 2
      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch.sort, deletion_reason: Codespace.deletion_reasons[:repository_made_private])
      end
      Codespaces::FindAffectedCodespacesByTeam.new(team_id: @team.id, deletion_reason: Codespace.deletion_reasons[:repository_made_private]).call
    end
  end
end unless GitHub.enterprise?
