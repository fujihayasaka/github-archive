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


  context "Test Cap check" do
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
