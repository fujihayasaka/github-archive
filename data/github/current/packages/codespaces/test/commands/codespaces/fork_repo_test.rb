# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

module Codespaces
  class ForkRepoTest < GitHub::TestCase
    include ConditionalAccess::FilterTestHelper

    def with_inline_repo_forking
      # This idea was taken from the `WithWorkingFork` module in another test.
      # Advice is a module in `test/test_helpers/advice.rb`
      advice_token = Advice.around(::Repository, :fork) do |_repo, callback|
        forked_repo = T.let(nil, T.nilable(::Repository))
        status = T.let(nil, T.nilable(Symbol))
        errors = T.let(nil, T.nilable(Array))

        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          forked_repo, status, errors = callback.call
        end
        forked_repo.reload if forked_repo
        [forked_repo, status, errors]
      end
      yield if block_given?
      Advice.unaround(advice_token)
    end

    def mint_github_token_for_user_and_codespace(user, codespace, expected_oauth_access_count: 1)
      Codespaces::Tokens.mint_github_token(user, codespace)

      assert_equal expected_oauth_access_count, OauthAccess
        .select(:installation_id)
        .where(user: user, installation_type: "SiteScopedIntegrationInstallation")
        .distinct
        .count

      non_expired_owner_installations = SiteScopedIntegrationInstallation
        .where(target: codespace.repository.owner)
        .where("expires_at > ?", Time.now.to_i)

      installations = non_expired_owner_installations.select do |ssii|
        OauthAccess.where(user: user, installation: ssii).where("expires_at_timestamp > ?", Time.now.to_i).any? &&
          ssii.codespace_ids == [codespace.id]
      end

      assert_equal 1, installations.count
      installations.first
    end

    def create_integration(options = {})
      make_trusted_oauth_apps_owner
      integration = create(:codespaces_integration, **options)
      integration.update!(user_token_expiration: true)
      integration
    end

    fixtures do
      @user = create(:user)
      disable_feature_flag(:codespaces_test_secret_escalation, @user)
    end

    test "it forks the repository (sync), creates branch and updates it from ref, creates billing entry and updates installation" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
        original_repository = codespace.repository
        original_billable_owner = codespace.billable_owner

        installation = mint_github_token_for_user_and_codespace(@user, codespace)

        forked, ref = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

        installation.reload

        assert_equal original_billable_owner, codespace.billable_owner
        assert_equal forked, codespace.repository
        assert_equal ref, "master"

        latest_billing_entry = Codespaces::BillingEntry.latest(codespace.guid)
        assert_equal forked, latest_billing_entry.repository
        assert_equal 2, Codespaces::BillingEntry.count
        assert_equal codespace.billable_owner, latest_billing_entry.billable_owner

        assert_same_elements [original_repository, forked], installation.repositories
      end
    end

    test "it uses existing fork, creates branch and updates it from ref, creates billing entry and updates installation" do
      create_integration

      public_repo = create(:repository, from_example: :simple)
      public_repo.heads.find_or_build("master")

      codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")

      fork_repo = create(:fork_repository, forker: @user, fork_repo: public_repo)
      fork_ref = fork_repo.heads.find_or_build("master")

      original_repository = codespace.repository
      original_billable_owner = codespace.billable_owner

      installation = mint_github_token_for_user_and_codespace(@user, codespace)

      forked, ref = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)
      self.assert_equal(fork_repo, forked)

      installation.reload

      assert_equal original_billable_owner, codespace.billable_owner
      assert_equal forked, codespace.repository
      assert_equal ref, "master"

      latest_billing_entry = Codespaces::BillingEntry.latest(codespace.guid)
      assert_equal forked, latest_billing_entry.repository
      assert_equal 2, Codespaces::BillingEntry.count
      assert_equal codespace.billable_owner, latest_billing_entry.billable_owner

      assert_same_elements [original_repository, forked], installation.repositories
    end

    test "it doesn't consider an existing parent to be a usable fork" do
      create_integration
      public_repo = create(:repository, owner: @user, from_example: :simple)
      public_repo.heads.find_or_build("master")
      with_inline_repo_forking do
        rando_user = create(:user)
        fork_repo = create(:fork_repository, forker: rando_user, fork_repo: public_repo)
        fork_ref = fork_repo.heads.find_or_build("master")
        codespace = create(:codespace, :unpushable, owner: @user, repository: fork_repo, ref: "master")

        assert_raises Codespaces::ForkRepo::UserOwnsParentRepository do
          Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)
        end
      end
    end

    test "it doesn't consider an existing grandparent to be a usable fork" do
      create_integration
      public_repo = create(:repository, owner: @user, from_example: :simple)
      public_repo.heads.find_or_build("master")
      with_inline_repo_forking do
        rando_user = create(:user)
        parent_fork_repo = create(:fork_repository, forker: rando_user, fork_repo: public_repo)
        fork_ref = parent_fork_repo.heads.find_or_build("master")

        rando_user2 = create(:user)
        fork_repo = create(:fork_repository, forker: rando_user2, fork_repo: parent_fork_repo)
        fork_ref = fork_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: fork_repo, ref: "master")

        assert_raises Codespaces::ForkRepo::UserOwnsParentRepository do
          Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)
        end
      end
    end

    test "it elevates all tokens associated with the integration's permissions" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
        mint_github_token_for_user_and_codespace(@user, codespace)
        user_oauth_accesses = OauthAccess.where(user: @user)
        assert_equal 1, user_oauth_accesses.count
        @user.oauth_access = user_oauth_accesses.first

        # simulate VS CS calling our api to mint a second GitHub token
        Codespaces::Tokens.mint_github_token(@user, codespace)

        # ensure we have two site scoped integration installations which recreates the behavior we see on prod
        # when we mint 2+ GitHub tokens for a codespace
        user_site_scoped_integration_installations = SiteScopedIntegrationInstallation
        .where(target: public_repo.owner).select do |ssii|
          OauthAccess.where(user: @user, installation: ssii).any?
        end

        assert_equal 2, user_site_scoped_integration_installations.length
        first_installation = user_site_scoped_integration_installations.first
        second_installation = user_site_scoped_integration_installations.second
        refute_equal first_installation, second_installation

        forked, _ = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

        first_installation&.reload
        second_installation&.reload

        assert_same_elements T.must(first_installation).reload.repository_ids, second_installation&.repository_ids
        assert T.must(first_installation).repository_ids.include?(forked.id)
        assert second_installation&.repository_ids.include?(forked.id)
        assert forked.resources.contents.writable_by?(first_installation)
        assert forked.resources.contents.writable_by?(second_installation)
      end
    end

    test "does not elevate permissions on installations associated with other codespaces or repositories" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        another_public_repo = create(:repository, from_example: :simple)
        another_public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
        same_repo_codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
        other_repo_codespace = create(:codespace, :unpushable, owner: @user, repository: another_public_repo, ref: "master")

        installation = mint_github_token_for_user_and_codespace(@user, codespace)
        same_repo_installation = mint_github_token_for_user_and_codespace(@user, same_repo_codespace, expected_oauth_access_count: 2)
        other_repo_installation = mint_github_token_for_user_and_codespace(@user, other_repo_codespace, expected_oauth_access_count: 3)

        same_repo_installation_repo_ids = same_repo_installation.repository_ids.dup
        other_repo_installation_repo_ids = other_repo_installation.repository_ids.dup

        forked, _ = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

        installation.reload

        assert installation.repository_ids.include?(forked.id)
        assert forked.resources.contents.writable_by?(installation)

        refute_same_elements installation.repository_ids, same_repo_installation_repo_ids
        assert_same_elements same_repo_installation_repo_ids, same_repo_installation.repository_ids
        refute forked.resources.contents.writable_by?(same_repo_installation)

        refute_same_elements installation.repository_ids, other_repo_installation_repo_ids
        assert_same_elements other_repo_installation_repo_ids, other_repo_installation.repository_ids
        refute forked.resources.contents.writable_by?(other_repo_installation)
      end
    end

    test "expired installations do not have their permissions elevated" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
        first_installation = T.let(nil, T.nilable(SiteScopedIntegrationInstallation))

        Timecop.travel(1.month.ago) do
          first_installation = mint_github_token_for_user_and_codespace(@user, codespace)
        end

        # first installation will be expired so expect 2
        second_installation = mint_github_token_for_user_and_codespace(@user, codespace, expected_oauth_access_count: 2)

        forked, _ = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

        first_installation&.reload
        second_installation.reload

        refute_same_elements first_installation&.repository_ids, second_installation.repository_ids
        refute first_installation&.repository_ids.include?(forked.id)
        assert second_installation.repository_ids.include?(forked.id)
        refute forked.resources.contents.writable_by?(first_installation)
        assert forked.resources.contents.writable_by?(second_installation)
      end
    end

    test "if upstream branch and forked branch diverged, then create new branch" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")

        fork_repo = create(:fork_repository, forker: @user, fork_repo: public_repo)
        fork_ref = fork_repo.heads.find_or_build("master")

        @commit_data = { message: "test commit", author: @user }
        fork_ref.append_commit(@commit_data, @user)

        new_forked, ref = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

        assert_match /codespace-\w{4}/, ref
      end
    end

    test "if branch doesn't exist in upstream branch, create in fork and return it" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")

        new_forked, ref = Codespaces::ForkRepo.call(codespace, "test", entry_point: :test_case)

        assert_equal "test", ref
      end
    end

    test "if branch is nil, return random branch" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")

        codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")

        new_forked, ref = Codespaces::ForkRepo.call(codespace, nil, entry_point: :test_case)

        assert_match /codespace-\w{4}/, ref
      end
    end

    test "only elevates permissions on installations associated with the codespace owner" do
      create_integration

      with_inline_repo_forking do
        public_repo = create(:repository, from_example: :simple)
        public_repo.heads.find_or_build("master")
        rando = create(:user)

        user_codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
        rando_codespace = create(:codespace, :unpushable, owner: rando, repository: public_repo, ref: "master")

        user_installation = mint_github_token_for_user_and_codespace(@user, user_codespace)
        rando_installation = mint_github_token_for_user_and_codespace(rando, rando_codespace)

        forked, _ = Codespaces::ForkRepo.call(user_codespace, "master", entry_point: :test_case)

        user_installation.reload
        rando_installation.reload

        refute_same_elements user_installation.repository_ids, rando_installation.repository_ids
        refute rando_installation.repository_ids.include?(forked.id)
        assert user_installation.repository_ids.include?(forked.id)
        refute forked.resources.contents.writable_by?(rando_installation)
        assert forked.resources.contents.writable_by?(user_installation)
      end
    end

    test "randos aren't granted access to other repo owner repositories as a result of fork_repo" do
      create_integration

      with_inline_repo_forking do
        org = create(:business_plus_org)
        public_repo = create(:repository, owner: org)
        other_public_repo = create(:repository, owner: org)
        private_repo = create(:private_repository, owner: org)

        [public_repo, other_public_repo, private_repo].each do |repo|
          example_repo :simple, repo
          repo.heads.find_or_build("master")
        end

        rando = create(:user)

        codespace = create(:codespace, :unpushable, owner: rando, repository: public_repo, ref: "master")
        installation = mint_github_token_for_user_and_codespace(rando, codespace)

        forked, _ = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

        installation.reload

        assert installation.repository_ids.include?(forked.id)
        assert forked.resources.contents.writable_by?(installation)
        assert public_repo.resources.contents.readable_by?(installation)
        refute other_public_repo.resources.contents.writable_by?(installation)
        refute private_repo.resources.contents.writable_by?(installation)
      end
    end

    test "it forks the repository (async), does not create branch, creates billing entry and updates installation" do
      create_integration

      public_repo = create(:repository, from_example: :simple)
      public_repo.heads.find_or_build("master")

      codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
      original_repository = codespace.repository
      original_billable_owner = codespace.billable_owner

      installation = mint_github_token_for_user_and_codespace(@user, codespace)

      forked, ref = Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)

      assert_equal original_billable_owner, codespace.billable_owner
      assert_equal forked, codespace.repository
      assert_match codespace.ref, ref

      latest_billing_entry = Codespaces::BillingEntry.latest(codespace.guid)
      assert_equal forked, latest_billing_entry.repository
      assert_equal 2, Codespaces::BillingEntry.count
      assert_equal codespace.billable_owner, latest_billing_entry.billable_owner

      assert_same_elements [original_repository, forked], installation.reload.repositories
    end

    test "raises UnforkableRepository if the repository cannot be forked" do
      create_integration

      unforkable_repo = create(:org_owned_private_repository)
      example_repo :simple, unforkable_repo

      codespace = create(:codespace, :unpushable, owner: @user, repository: unforkable_repo)

      assert_raises Codespaces::ForkRepo::UnforkableRepository do
        Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)
      end
    end

    test "raises ArgumentError if the installation is nil" do
      create_integration

      public_repo = create(:repository, from_example: :simple)
      public_repo.heads.find_or_build("master")

      codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")

      assert_raises ArgumentError do
        Codespaces::ForkRepo.call(codespace, "master", nil, entry_point: :test_case)
      end
    end

    test "raises InstallationUpdateFailed if appending a SiteScopedIntegrationInstallation's permissions fails" do
      create_integration

      public_repo = create(:repository, from_example: :simple)
      public_repo.heads.find_or_build("master")

      codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")
      SiteScopedIntegrationInstallation::Editors::Repository.expects(:grant).returns(
        SiteScopedIntegrationInstallation::Editors::Result.failed(:invalid_permissions)
      )
      installation = mint_github_token_for_user_and_codespace(@user, codespace) # Need at least one to hit stub

      assert_raises Codespaces::ForkRepo::InstallationUpdateFailed do
        Codespaces::ForkRepo.call(codespace, "master", entry_point: :test_case)
      end
    end
  end unless GitHub.enterprise?
end
