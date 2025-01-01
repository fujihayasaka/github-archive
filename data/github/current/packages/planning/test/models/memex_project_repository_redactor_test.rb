# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectRepositoryRedactorTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @admin = create(:verified_user)
    @external_identity = create :external_identity
    @saml_org = @external_identity.target
    @saml_org.add_member(@admin, action: :admin)
    @repo = create(:private_repository, owner: @saml_org)
    @public_repo = create(:public_repository, owner: @saml_org)

    @other_saml_org = create(:external_identity).target
    @other_org_repo = create(:private_repository, owner: @other_saml_org)

    @org_memex = create(:memex_project, owner: @saml_org)

    # Non saml org
    @org_2 = create(:organization)
    @org_2.add_member(@admin, action: :admin)
    @repo_2 = create(:private_repository, owner: @org_2)
  end


  context "Enterprise and CAP checks" do
    test "Test authorized repos for SAML org with user having read access to repo" do
      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: @admin,
        repo_ids: [@repo.id, @public_repo.id]
      )

      repos = redactor.authorized_repo_ids
      assert_equal repos.length, 2
    end

    test "Test authorized repos for SAML org with user not having read access to private repo" do
      # create a random user with no access to repo
      @user = create(:verified_user)
      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: @user,
        repo_ids: [@repo.id, @public_repo.id]
      )

      repos = redactor.authorized_repo_ids
      assert_equal repos.length, 1 # One public repo
    end

    test "Test authorized repos for Non SAML org with user having read access to repo" do
      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: @admin,
        repo_ids: [@repo.id, @repo_2.id]
      )

      repos = redactor.authorized_repo_ids
      assert_equal repos.length, 2
    end

    test "cap check" do
      saml_org_1 = create(:business_plus_org)
      saml_org_2 = create(:business_plus_org)
      saml_identity_1 = create(:external_identity, org: saml_org_1)
      saml_identity_2 = create(:external_identity, org: saml_org_2)
      saml_user = saml_identity_1.user

      saml_repo_1 = create(:private_repository, owner: saml_org_1)
      saml_repo_2 = create(:private_repository, owner: saml_org_2)

      saml_repo_1.add_member_without_validation_or_notifications(saml_user, action: :read)

      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: saml_user,
        repo_ids: [saml_repo_1.id, saml_repo_2.id]
      )

      repos = redactor.authorized_repo_ids
      assert_equal repos.length, 1
    end

    test "Authorized for internal repositories when a member of the enterprise but not the repo org" do
      business = create(:business)
      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      org1_user = create(:user)
      org1.add_member(org1_user)

      org1_private_repo = create(:private_repository, owner: org1)
      org2_private_repo = create(:private_repository, owner: org2)
      org1_internal_repo = create(:internal_repository, owner: org1)
      org2_internal_repo = create(:internal_repository, owner: org2)

      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: org1_user,
        repo_ids: [org1_private_repo.id, org2_private_repo.id, org1_internal_repo.id, org2_internal_repo.id]
      )

      # Expect to have access to all internal repositories in the business, even if the user is not a member of all orgs
      assert org1_user.organization_ids.include?(org1.id)
      refute org1_user.organization_ids.include?(org2.id)
      expected_repo_ids = [org1_private_repo.id, org1_internal_repo.id, org2_internal_repo.id]
      assert_same_elements expected_repo_ids, redactor.authorized_repo_ids
    end

    test "guest collaborators cannot access internal repos in orgs that they do not belong to", skip_enterprise: true do
      emu_owner = create :emu, :owner
      business = emu_owner.enterprise_managed_business

      org1 = create :organization, business: business, admin: emu_owner
      org2 = create :organization, business: business, admin: emu_owner

      guest_collaborator = create :emu, :guest_collaborator, business: business
      org1.add_member(guest_collaborator)

      org1_repos_ids = [create(:private_repository, owner: org1).id, create(:internal_repository, owner: org1).id]
      org2_repos_ids = [create(:private_repository, owner: org2).id, create(:internal_repository, owner: org2).id]

      # Double check org membership for the guest collaborator
      assert org1.member?(guest_collaborator)
      assert guest_collaborator.organization_ids.include?(org1.id)
      refute org2.member?(guest_collaborator)
      refute guest_collaborator.organization_ids.include?(org2.id)

      # MemexProjectRepositoryRedactor uses Repository Authz
      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: guest_collaborator,
        repo_ids: org1_repos_ids + org2_repos_ids
      )

      org1_visible_repos_ids = org1.reload.visible_repositories_for(guest_collaborator).map(&:id)
      org2_visible_repos_ids = org2.reload.visible_repositories_for(guest_collaborator).map(&:id)
      visible_repos_ids = org1_visible_repos_ids + org2_visible_repos_ids

      # Expect to have access all org1 repositories (private and internal) where the guest_collaborator was added as a member.
      # Guest collaborators should not have access to private or internal repositories of other orgs within the business.
      # See https://docs.github.com/en/enterprise-cloud@latest/admin/managing-accounts-and-repositories/managing-users-in-your-enterprise/roles-in-an-enterprise#guest-collaborators

      assert_same_elements org1_repos_ids, visible_repos_ids
      assert_same_elements org1_repos_ids, redactor.authorized_repo_ids
    end

    test "makes efficient use of the database" do
      rando = create(:verified_user)
      repos = [@repo, @public_repo, @other_org_repo] + create_list(:private_repository, 8, owner: @saml_org)
      redactor = MemexProjectRepositoryRedactor.new(
        cap_filter: cap_authorizing_filter,
        user: rando,
        repo_ids: repos.map(&:id),
      )

      # The number of queries we issue should be strictly less than the number of repositories we're
      # authorizing (i.e. no N+1 query patterns).
      #
      # The actual number of queries we issue at time of writing is 5, and those queries span multiple tables. We
      # allow for one more query than that so that this test doesn't flake for a minor addition. That means that if
      # we do need to change this number, we should consider carefully whether or not this process is still reasonably
      # efficient.
      expected_max_query_count = 6
      assert expected_max_query_count < repos.length

      authorized_repo_ids = assert_max_query_count(expected_max_query_count, ignore_feature_flags: true) do
        redactor.authorized_repo_ids
      end

      assert_equal [@public_repo.id], authorized_repo_ids
    end
  end
end
