# typed: true
# frozen_string_literal: true

require "test_helper"

class Configurable::RepositoryFundingLinksTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)

    @org = create(:organization)
    @global_health_files_repo = create(:repository, owner: @org, name: Repository::GLOBAL_HEALTH_FILES_NAME,
      from_example: :simple)
  end

  context "#repository_funding_links_explicitly_enabled? and #async_repository_funding_links_explicitly_enabled?" do
    test "returns true when setting has been enabled for repository" do
      @repo.enable_repository_funding_links(actor: @repo.owner)
      assert_predicate @repo, :repository_funding_links_explicitly_enabled?
      assert @repo.async_repository_funding_links_explicitly_enabled?.sync
    end

    test "returns false when setting has not been set for the repository" do
      refute_predicate @repo, :repository_funding_links_explicitly_enabled?
      refute @repo.async_repository_funding_links_explicitly_enabled?.sync
    end

    test "returns false when setting has been explicitly disabled for the repository" do
      @repo.disable_repository_funding_links(actor: @repo.owner)
      refute_predicate @repo, :repository_funding_links_explicitly_enabled?
      refute @repo.async_repository_funding_links_explicitly_enabled?.sync
    end
  end

  context "#disable_repository_funding_links" do
    test "enqueues job to update repository sponsorables" do
      assert_enqueued_with(
        job: UpdateRepositorySponsorablesForRepositoryJob,
        args: [{ repository_id: @repo.id }],
      ) do
        assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
          @repo.disable_repository_funding_links(actor: @repo.owner)
        end
      end
    end if GitHub.sponsors_enabled?

    test "enqueues jobs to update repository sponsorables for global health files repository" do
      assert_enqueued_with(
        job: UpdateRepositorySponsorablesForGlobalRepoJob,
        args: [{ repository_id: @global_health_files_repo.id }],
      ) do
        assert_enqueued_with(
          job: UpdateRepositorySponsorablesForRepositoryJob,
          args: [{ repository_id: @global_health_files_repo.id }],
        ) do
          @global_health_files_repo.disable_repository_funding_links(actor: @org.admins.first)
        end
      end
    end if GitHub.sponsors_enabled?

    test "does not enqueue a job when setting is already disabled" do
      @repo.disable_repository_funding_links(actor: @repo.owner)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
          @repo.disable_repository_funding_links(actor: @repo.owner)
        end
      end
    end

    test "does not enqueue a job when setting is already disabled on global health repository" do
      @global_health_files_repo.disable_repository_funding_links(actor: @org.admins.first)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
          @global_health_files_repo.disable_repository_funding_links(actor: @org.admins.first)
        end
      end
    end
  end

  context "#repository_funding_links_unset? and #async_repository_funding_links_unset?" do
    test "returns false when setting has been enabled for repository" do
      @repo.enable_repository_funding_links(actor: @repo.owner)
      refute_predicate @repo, :repository_funding_links_unset?
      refute @repo.async_repository_funding_links_unset?.sync
    end

    test "returns true when setting has not been set for the repository" do
      assert_predicate @repo, :repository_funding_links_unset?
      assert @repo.async_repository_funding_links_unset?.sync
    end

    test "returns false when setting has been explicitly disabled for the repository" do
      @repo.disable_repository_funding_links(actor: @repo.owner)
      refute_predicate @repo, :repository_funding_links_unset?
      refute @repo.async_repository_funding_links_unset?.sync
    end
  end

  context "#enable_repository_funding_links" do
    test "enqueues job to update repository sponsorables" do
      assert_enqueued_with(
        job: UpdateRepositorySponsorablesForRepositoryJob,
        args: [{ repository_id: @repo.id }],
      ) do
        assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
          @repo.enable_repository_funding_links(actor: @repo.owner)
        end
      end
    end if GitHub.sponsors_enabled?

    test "enqueues job to update repository sponsorables for global health files repository" do
      assert_enqueued_with(
        job: UpdateRepositorySponsorablesForGlobalRepoJob,
        args: [{ repository_id: @global_health_files_repo.id }],
      ) do
        assert_enqueued_with(
          job: UpdateRepositorySponsorablesForRepositoryJob,
          args: [{ repository_id: @global_health_files_repo.id }],
        ) do
          @global_health_files_repo.enable_repository_funding_links(actor: @org.admins.first)
        end
      end
    end if GitHub.sponsors_enabled?

    test "does not enqueue a job when setting is already enabled" do
      @repo.enable_repository_funding_links(actor: @repo.owner)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
          @repo.enable_repository_funding_links(actor: @repo.owner)
        end
      end
    end

    test "does not enqueue a job when setting is already enabled on global health repository" do
      @global_health_files_repo.enable_repository_funding_links(actor: @org.admins.first)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
          @global_health_files_repo.enable_repository_funding_links(actor: @org.admins.first)
        end
      end
    end
  end
end
