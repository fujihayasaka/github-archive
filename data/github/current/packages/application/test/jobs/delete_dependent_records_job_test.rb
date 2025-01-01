# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeleteDependentRecordsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @owner = create :user, plan: "medium", login: "owner"
    @forker  = create :user, plan: "medium", login: "forker"

    @source = create :repository, owner: @owner, from_example: :pull_request_source

    # Initiate Repository deletion
    @source.remove(@owner)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "retries the job if a throttling error occurs" do
    GitHub::Throttler::Null.any_instance.stubs(:throttle).raises(Freno::Throttler::Error)

    repo = create(:repository)
    create :commit_contribution, repository: repo

    args = ["Repository", repo.id, :commit_contributions, {}]
    DeleteDependentRecordsJob.any_instance.expects(:retry_job)
    DeleteDependentRecordsJob.perform_now *args
  end

  test "retries on dirty exit" do
    repo = create(:repository)
    assert_retry_on_dirty_exit job: DeleteDependentRecordsJob, args: ["Repository", repo.id, :commit_contributions]
  end

  test "does not raise with no arguements" do
    assert_equal "background_destroy", DeleteDependentRecordsJob.new.queue_name
  end

  [false, true].each do |inverse_relationship|
    context "inverse_relationship: #{inverse_relationship}" do
      test "it removes the dependent records referring to a model" do
        repo = create(:repository)
        3.times { create :commit_contribution, repository: repo }

        assert_difference("CommitContribution.count", -3) do
          perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
            if inverse_relationship
              DeleteDependentRecordsJob.perform_later("CommitContribution", repo.id, :repository, inverse_relationship:)
            else
              DeleteDependentRecordsJob.perform_later("Repository", repo.id, :commit_contributions)
            end
          end
        end
      end

      test "it only deletes what it's supposed to" do
        repo = create(:repository)
        3.times { create :commit_contribution, repository: repo }
        other_repo = create(:repository)
        3.times { create :commit_contribution, repository: other_repo }

        assert_equal 3, CommitContribution.for_repository(repo).count

        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          if inverse_relationship
            DeleteDependentRecordsJob.perform_later("CommitContribution", repo.id, :repository, inverse_relationship:)
          else
            DeleteDependentRecordsJob.perform_later("Repository", repo.id, :commit_contributions)
          end
        end

        assert_equal 0, CommitContribution.for_repository(repo).count
        assert_equal 3, CommitContribution.for_repository(other_repo).count
      end

      test "scopes deletions for polymorphic associations" do
        # create an organization and repo with same user id
        # orgs coexist with users, so find or create repo with the org's id, not a
        # an org with a repo's id (since a user with that id could exist)
        org = create(:organization)
        repo = Repository.find_by(id: org.id)
        if !repo
          repo = create(:repository, owner: org)
          repo.update_column(:id, org.id)
        end

        # Hooks
        hook = create(:hook, :org, installation_target: org)
        repo_hook = create(:hook, installation_target: repo)

        assert_equal 1, org.hooks.count
        assert_equal 1, repo.repo_hook_associations_ff? ? Hook.hooks_for_target(repo).count : repo.hooks.count
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          if inverse_relationship
            DeleteDependentRecordsJob.perform_later("Hook", repo.id, :installation_target, polymorphic_type_value: "Repository", inverse_relationship:)
          else
            DeleteDependentRecordsJob.perform_later("Repository", repo.id, :hooks)
          end
        end
        assert_equal 1, org.hooks.reload.count, "org hook should not have been deleted"
        assert_equal 0, repo.reload.hooks.count, "repo hooks should have been deleted"
        assert_equal org.id, hook.installation_target_id, "hook installation id should match org id"
        assert_equal repo.id, hook.installation_target_id, "hook installation id should match repo id"

        # Projects
        project = create(:org_project, owner: org)
        repo_project = create(:project, owner: repo)

        assert_equal 1, org.projects.count
        assert_equal 1, repo.projects.count
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          if inverse_relationship
            DeleteDependentRecordsJob.perform_later("Project", repo.id, :owner, polymorphic_type_value: "Repository", inverse_relationship:)
          else
            DeleteDependentRecordsJob.perform_later("Repository", repo.id, :projects)
          end
        end
        assert_equal 1, org.projects.reload.count, "org projects should not have been deleted"
        assert_equal 0, repo.projects.reload.count, "repo projects should have been deleted"
        assert_equal org.id, project.owner_id, "org project owner id should match org id"
        assert_equal repo.id, project.owner_id, "org project owner id should match repo id"
      end

      test "scopes deletions for polymorphic associations with custom values" do
        listing_featured_item = create(:sponsors_listing_featured_item)
        repo = listing_featured_item.featureable

        assert_equal 1, repo.sponsors_listing_featured_items.count
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          if inverse_relationship
            DeleteDependentRecordsJob.perform_later(
              "SponsorsListingFeaturedItem",
              repo.id,
              :featureable,
              polymorphic_type_value: listing_featured_item.featureable_type_before_type_cast,
              inverse_relationship:
            )
          else
            DeleteDependentRecordsJob.perform_later(
              "Repository",
              repo.id,
              :sponsors_listing_featured_items,
              polymorphic_type_value: listing_featured_item.featureable_type_before_type_cast
            )
          end
        end
        assert_equal 0, repo.sponsors_listing_featured_items.count, "sponsors_listing_featured_items should have been deleted"
      end

      test "deletes associations with sharding information" do
        repo = create :repository, from_example: :simple
        status = create(:status, repository: repo)

        assert_difference("Status.where(repository_id: #{repo.id}).count", -1) do
          if inverse_relationship
            DeleteDependentRecordsJob.perform_now("Status", repo.id, :repository, sharding_key: :repository_id, sharding_value: repo.id, inverse_relationship:)
          else
            DeleteDependentRecordsJob.perform_now("Repository", repo.id, :statuses, sharding_key: :repository_id, sharding_value: repo.id)
          end
        end
      end

      test "deleting Storage::Uploadable objects dereferences the Storage::Blob" do
        GitHub.storage_cluster_enabled = true

        user = create(:user)
        repo = create :repository, owner: user, from_example: :repository_test_simple

        blob = Storage::Blob.create_for_uploadable(
          oid: Sham.sha256,
          size: 123,
        )
        release = create :release, repository: repo, author: user, tag_name: "v1"
        asset = create :release_asset, uploader: user, release: release, storage_blob: blob, size: blob.size, oid: blob.oid, name: "ayp.wtf.cat"
        GitHub::Storage::Creator.create_uploadable_references([asset])

        assert GitHub::Storage::Destroyer.count_references([blob])[blob.id] > 0
        assert asset.valid?, asset.errors.inspect
        assert_equal Storage::Purge.count, 0

        assert_difference("Storage::Purge.count", +1) do
          perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
            if inverse_relationship
              DeleteDependentRecordsJob.perform_later("ReleaseAsset", repo.id, :repository, inverse_relationship:)
            else
              DeleteDependentRecordsJob.perform_later("Repository", repo.id, :release_assets)
            end
          end
        end
      end

      test "uses the dependent model's connection" do
        team = create :team
        post = create(:discussion_post, team: team)

        assert_equal 1, DiscussionPost.where(team_id: team.id).count

        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          if inverse_relationship
            DeleteDependentRecordsJob.perform_later("DiscussionPost", team.id, :team, inverse_relationship:)
          else
            DeleteDependentRecordsJob.perform_later("Team", team.id, :discussion_posts)
          end
        end

        assert_equal 0, DiscussionPost.where(team_id: team.id).count
      end

      context ".custom_queue_name" do
        test "uses dedicated queue when set" do
          ApplicationRecord::IssuesPullRequests.stub(:dedicated_background_destroy_queue_name, :background_destroy_issues_pull_requests) do
            if inverse_relationship
              job = DeleteDependentRecordsJob.perform_later("Issue", @source.id, :repository, inverse_relationship:)
            else
              job = DeleteDependentRecordsJob.perform_later("Repository", @source.id, :issues)
            end
            assert_equal "background_destroy_issues_pull_requests", job.queue_name
          end
        end

        test "uses default queue when not set" do
          ApplicationRecord::IssuesPullRequests.stub(:dedicated_background_destroy_queue_name, nil) do
            if inverse_relationship
              job = DeleteDependentRecordsJob.perform_later("Issue", @source.id, :repository, inverse_relationship:)
            else
              job = DeleteDependentRecordsJob.perform_later("Repository", @source.id, :issues)
            end
            assert_equal "background_destroy", job.queue_name
          end
        end
      end
    end
  end
end
