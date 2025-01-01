# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDBTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  context ".collaborator?" do
    test "returns false if no user (i.e. signed out)" do
      refute AdvisoryDB::collaborator?(repository: create(:repository), user: nil)
    end

    test "returns false if user has no permissions" do
      user = create(:user)
      repository = create(:repository)

      refute AdvisoryDB::collaborator?(repository: repository, user: user)
    end

    test "returns true if user owns the repository" do
      user = create(:user)
      repository = create(:repository, owner: user)

      assert AdvisoryDB::collaborator?(repository: repository, user: user)
    end

    test "returns true if user is a repository admin" do
      user = create(:user)
      organization = create(:business_plus_org)
      repository = create(:repository, owner: organization)
      repository.add_member(user, action: :admin)

      assert AdvisoryDB::collaborator?(repository: repository, user: user)
    end

    test "returns true if user is organization admin" do
      user = create(:user)
      organization = create(:business_plus_org, admin: user)
      repository = create(:repository, owner: organization)

      assert AdvisoryDB::collaborator?(repository: repository, user: user)
    end

    test "returns true if user is part of the security manager team" do
      user = create(:user)
      organization = create(:business_plus_org)
      security_manager_team = create(:security_manager_team, organization: organization)
      security_manager_team.add_member(user)
      repository = create(:repository, owner: organization)

      assert AdvisoryDB::collaborator?(repository: repository, user: user)
    end

    test "returns true if user has fine-grained permissions for code scanning", skip_enterprise: true do
      [:read_code_scanning, :write_code_scanning, :delete_alerts_code_scanning].each do |fgp|
        user = create(:user)
        organization = create(:business_plus_org)
        repository = create(:repository, owner: organization)
        grant_custom_role(user: user, target: repository, fgps: [fgp])

        assert AdvisoryDB::collaborator?(repository: repository, user: user)
      end
    end

    test "returns true if user has fine-grained permissions for dependabot alerts" do
      user = create(:user)
      organization = create(:business_plus_org)
      repository = create(:repository, owner: organization)
      grant_custom_role(user: user, target: repository, fgps: [:view_dependabot_alerts])

      assert AdvisoryDB::collaborator?(repository: repository, user: user)

      grant_custom_role(user: user, target: repository, fgps: [:resolve_dependabot_alerts])
      assert AdvisoryDB::collaborator?(repository: repository, user: user)
    end

    test "returns true if user has fine-grained permissions for secret scanning" do
      user = create(:user)
      organization = create(:business_plus_org)
      repository = create(:repository, owner: organization)
      grant_custom_role(user: user, target: repository, fgps: [:view_secret_scanning_alerts])
      assert AdvisoryDB::collaborator?(repository: repository, user: user)
    end
  end
end
