# typed: true
# frozen_string_literal: true

require "test_helper"

module ProgrammaticActor
  class RepositoryFilterTest < GitHub::TestCase
    include ApiProgrammaticGrantHelpers

    fixtures do
      @user = create(:user)
    end

    def described_class
      ::ProgrammaticActor::RepositoryFilter
    end

    context ".applicable?" do
      test "returns true for user-to-server requests" do
        grant = create(:github_app_access, user: @user, entry_point: :test_case)
        @user.oauth_access = grant

        assert_predicate @user, :using_auth_via_integration?
        assert described_class.applicable?(@user)
      end

      test "returns true for user programmatic access requests" do
        access = create(:user_programmatic_access, owner: @user)
        @user.programmatic_access = access

        assert_predicate @user, :using_auth_via_user_programmatic_access?
        assert described_class.applicable?(@user)
      end

      test "returns false for server-to-server requests" do
        installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        bot = installation.bot

        refute described_class.applicable?(bot)
      end

      test "returns false for oauth type requests" do
        pat = create(:oauth_access, :personal_token, user: @user)
        oauth_access = create(:oauth_access, user: @user)

        @user.oauth_access = pat
        assert_predicate @user, :using_personal_access_token?
        refute described_class.applicable?(@user)

        @user.oauth_access = oauth_access
        assert_predicate @user, :using_auth_via_oauth_application?
        refute described_class.applicable?(@user)
      end

      test "returns false for non-users" do
        refute described_class.applicable?(create(:organization))
      end
    end

    context ".perform" do
      test "filters user-to-server requests" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        installation = make_integration_installation(repository: repo1, permissions: { "metadata" => :read })

        grant = installation.integration.grant(@user, entry_point: :test_case)
        @user.oauth_access = grant

        filtered_ids = described_class.perform(actor: @user, repository_ids: [repo1.id, repo2.id])
        assert_equal [repo1.id], filtered_ids
      end

      test "filters user-to-server requests with installation from target" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        installation = make_integration_installation(repository: repo1, permissions: { "metadata" => :read })
        repository_ids = [repo1.id, repo2.id]

        Integration.any_instance
        .expects(:accessible_repository_ids)
        .with(repository_ids: repository_ids, current_integration_installation: installation)
        .returns([repo1.id])

        grant = installation.integration.grant(@user, entry_point: :test_case)
        @user.oauth_access = grant

        assert_nil @user.oauth_access.installation
        # We expect the installation to be found from the target
        filtered_ids = described_class.perform(actor: @user, repository_ids: repository_ids, target: @user)
        assert_equal [repo1.id], filtered_ids
      end

      test "filters user programmatic access requests" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        @user.programmatic_access = make_user_programmatic_access_with_grant(
          requester: @user, repositories: [repo1], permissions: { "metadata" => :read },
        )

        filtered_ids = described_class.perform(actor: @user, repository_ids: [repo1.id, repo2.id])
        assert_equal [repo1.id], filtered_ids
      end

      test "filters by resource" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        @user.programmatic_access = make_user_programmatic_access_with_grant(
          requester: @user, repositories: [repo1], permissions: { "metadata" => :read },
        )

        filtered_ids = described_class.perform(actor: @user, repository_ids: [repo1.id, repo2.id], resource: "issues")
        assert_empty filtered_ids
      end

      test "allows the filtered repositories to be augmented" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        @user.programmatic_access = make_user_programmatic_access_with_grant(
          requester: @user, repositories: [repo1], permissions: { "metadata" => :read },
        )

        # Custom code that should be applied to the filtered repositories.
        # In this example, we arbitrarily append a repository that the actor
        # does not have explicit access to via fine-grained permissions.

        # rubocop:disable Lint/UnusedBlockArgument
        augmentation = ->(actor:, repository_ids:, resource:, accessible_repository_ids:) {
          accessible_repository_ids << repo2.id
        }
        # rubocop:enable Lint/UnusedBlockArgument

        filtered_ids = described_class.perform(actor: @user, repository_ids: [repo1.id, repo2.id], augmentation: augmentation)
        assert_equal [repo1.id, repo2.id], filtered_ids
      end

      test "removes duplicates after augmentation" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        @user.programmatic_access = make_user_programmatic_access_with_grant(
          requester: @user, repositories: [repo1], permissions: { "metadata" => :read },
        )

        # Custom code that should be applied to the filtered repositories.
        # In this example, we arbitrarily append a repository that the actor
        # does not have explicit access to via fine-grained permissions.

        # rubocop:disable Lint/UnusedBlockArgument
        augmentation = ->(actor:, repository_ids:, resource:, accessible_repository_ids:) {
          accessible_repository_ids << repo2.id
          accessible_repository_ids << repo2.id
        }
        # rubocop:enable Lint/UnusedBlockArgument

        filtered_ids = described_class.perform(actor: @user, repository_ids: [repo1.id, repo2.id], augmentation: augmentation)
        assert_equal [repo1.id, repo2.id], filtered_ids
      end

      test "does not filter non-applicable request types" do
        repo1 = create(:repository, :minimal, owner: @user)
        repo2 = create(:repository, :minimal, owner: @user)

        installation = make_integration_installation(repository: repo1, permissions: { "metadata" => :read })
        bot = installation.bot

        filtered_ids = described_class.perform(actor: bot, repository_ids: [repo1.id, repo2.id])
        assert_same_elements [repo1.id, repo2.id], filtered_ids
      end
    end
  end
end
