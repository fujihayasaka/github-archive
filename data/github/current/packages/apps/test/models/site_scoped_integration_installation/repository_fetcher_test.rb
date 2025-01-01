# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteScopedIntegrationInstallation::RepositoryFetcherTest < GitHub::TestCase

  fixtures do
    @user        = create(:user)
    @repository  = create(:repository, :minimal, owner: @user)
  end

  context ".fetch" do
    test "returns :all if repository ids or repository names not provided" do
      result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        @user,
      )

      assert_predicate result, :success?
      assert_equal :all, result.repositories
    end

    test "returns repositories for given repository ids" do
      repository_ids = [@repository.id]
      result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        @user,  repository_ids: repository_ids,
      )

      assert_predicate result, :success?
      assert_same_elements [@repository], result.repositories
    end

    test "returns repositories for given repository ids and repository names" do
      @repository2 = create(:repository, :minimal, owner: @user)
      repository_ids = [@repository.id]
      repository_names = [@repository2.name]

      result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        @user,  repository_ids: repository_ids, repository_names: repository_names,
      )

      assert_predicate result, :success?
      assert_same_elements [@repository, @repository2], result.repositories
    end

    test "returns repositories for given repository visibility" do
      @org = create(:organization, business: (create :business))
      @repository2 = create(:repository, :minimal, owner: @org)
      @repository2.set_visibility(actor: @org, visibility: "internal")
      repository_ids = [@repository2.id]

      result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        @org,  repository_ids: repository_ids, visibility: "internal"
      )

      assert_predicate result, :success?
      assert_same_elements [@repository2], result.repositories
    end

    test "fails when given repository names is not accessible by target" do
      repository_names = [@repository.name, "non-existent-repo"]

      result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        @user, repository_names: repository_names,
      )

      refute_predicate result, :success?
      expected_message = "There is at least one repository that does not exist or is not accessible by the target."
      assert_equal expected_message, result.error
    end

    test "fails when given repository is not consistent with visibility" do
      repository_ids = [@repository.id]

      result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        @user,  repository_ids: repository_ids, visibility: "internal"
      )

      refute_predicate result, :success?
      expected_message = "There is at least one repository that does not match with given visibility."
      assert_equal expected_message, result.error
    end

    test "fails when given repository ids are exceeding MAX_REPOSITORY_IDS" do
      @repository2 = create(:repository, :minimal, owner: @user)
      SiteScopedIntegrationInstallation::RepositoryFetcher.stub_const(:MAX_REPOSITORY_IDS, 1) do
        repository_ids = [@repository.id, @repository2.id]

        result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
          @user,  repository_ids: repository_ids,
        )

        refute_predicate result, :success?
        assert_match /Too many repositories for installation/, result.error
      end
    end
  end
end
