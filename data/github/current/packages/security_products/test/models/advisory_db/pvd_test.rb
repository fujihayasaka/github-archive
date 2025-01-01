# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDbPvdTest < GitHub::TestCase
  skip_with_all_emus

  fixtures do
    @owner = create(:user)
    @public_repo = create(:repository, owner: @owner)
    @private_repo = create(:private_repository, owner: @owner)

    @archived_repo = create(:repository, owner: @owner)
    @archived_repo.set_archived

    @user = create(:user)
    @spammy_user = create(:spammy_user)

    @blocked_user = create(:user)
    @owner.block(@blocked_user)

    @collaborator = create(:user)
    @public_repo.add_member(@collaborator, action: :read)

    @admin = create(:user)
    @public_repo.add_member(@admin, action: :admin)

    @emu = create(:emu) unless GitHub.enterprise?
  end

  def setup
    SecurityProduct::PrivateVulnerabilityReporting.new(@public_repo).enable(actor: @owner)

    @subject = AdvisoryDB::Pvd
  end

  context ".authorized?" do
    unless GitHub.single_or_multi_tenant_enterprise?
      test "authorized when repo and user are both authorized" do
        assert @subject.authorized?(repo: @public_repo, user: @user)
      end

      test "unauthorized if repo is not authorized" do
        refute @subject.authorized?(repo: @private_repo, user: @user)
      end

      test "unauthorized if user is not authorized" do
        refute @subject.authorized?(repo: @public_repo, user: @blocked_user)
      end
    end
  end

  context ".authorized_repo?" do
    if GitHub.single_or_multi_tenant_enterprise?
      test "unauthorized on enterprise because repo security advisories aren't supported there" do
        refute @subject.authorized_repo?(repo: @public_repo)
      end
    else
      test "authorized on public repo if repo setting is enabled" do
        assert @public_repo.private_vulnerability_reporting_enabled?
        assert @subject.authorized_repo?(repo: @public_repo)
      end

      test "unauthorized on public repo if repo setting is not enabled" do
        SecurityProduct::PrivateVulnerabilityReporting.new(@public_repo).disable(actor: @owner)
        refute @public_repo.private_vulnerability_reporting_enabled?
        refute @subject.authorized_repo?(repo: @public_repo)
      end

      test "unauthorized on private repo" do
        refute @subject.authorized_repo?(repo: @private_repo)
      end

      test "unauthorized on archived repo" do
        refute @subject.authorized_repo?(repo: @archived_repo)
      end

      test "unauthorized if repo is innersource authorized" do
        assert @public_repo.private_vulnerability_reporting_enabled?
        assert @subject.authorized_repo?(repo: @public_repo)

        AdvisoryDB::Innersource.stubs(:repo_authorized?).returns(true)

        refute @public_repo.private_vulnerability_reporting_enabled?
        refute @subject.authorized_repo?(repo: @public_repo)
      end
    end
  end

  context ".authorized_user?" do
    if GitHub.single_or_multi_tenant_enterprise?
      test "unauthorized on enterprise because repo security advisories aren't supported there" do
        refute @subject.authorized_user?(repo: @public_repo, user: @user)
      end
    else
      test "authorized on user with read access to the repo" do
        assert @subject.authorized_user?(repo: @public_repo, user: @user)
      end

      test "unauthorized on logged out user" do
        refute @subject.authorized_user?(repo: @public_repo, user: nil)
      end

      test "unauthorized on user who is blocked by repo owner" do
        refute @subject.authorized_user?(repo: @public_repo, user: @blocked_user)
      end

      test "authorized on repo collaborator (not security manager)" do
        assert @subject.authorized_user?(repo: @public_repo, user: @collaborator)
      end

      test "unauthorized on repo admin" do
        refute @subject.authorized_user?(repo: @public_repo, user: @public_repo.owner)
      end

      test "unauthorized on user limited by user owned repo interactions" do
        repo_interactions = RepositoryInteractionAbility.new(@public_repo)
        # set interaction limit to be REPO collaborator ONLY
        assert repo_interactions.set_ability(:collaborators_only, @owner)
        assert repo_interactions.collaborators_only_enabled?
        # create a user that is not a collaborator
        user = create(:user)
        # new user should not be restricted by REPO collaborator limit
        assert RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @public_repo, user)
        # new user should not be authorized for private vulnerability disclosure
        refute @subject.authorized_user?(repo: @public_repo, user: user)
      end

      test "authorized on org member who are not limited by org owned repo interactions" do
        org = create(:organization, admin: @owner)
        org_repo = create(:repository, owner: org)
        org_repo_interactions = RepositoryInteractionAbility.new(org_repo)
        # set interaction limit to be REPO collaborator ONLY
        assert org_repo_interactions.set_ability(:collaborators_only, @owner)
        assert org_repo_interactions.collaborators_only_enabled?
        # create a user that is a REPO collaborator
        user = create(:user)
        org_repo.add_member(user)

        # new user should not be restricted by ORG REPO collaborator limit
        refute RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, org_repo, user)
        # new user should be authorized for private vulnerability disclosure
        assert @subject.authorized_user?(repo: org_repo, user: user)
      end

      test "unauthorized on spammy users by default", spammy_only: true do
        refute @subject.authorized_user?(repo: @public_repo, user: @spammy_user)
      end

      test "authorized on spammy users with optional flag", spammy_only: true do
        assert @subject.authorized_user?(repo: @public_repo, user: @spammy_user, check_spammy: false)
      end

      test "unauthorized on EMUs", skip_enterprise: true do
        refute @subject.authorized_user?(repo: @public_repo, user: @emu)
      end
    end
  end
end
