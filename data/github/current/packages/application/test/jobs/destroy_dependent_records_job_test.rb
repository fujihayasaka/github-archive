# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DestroyDependentRecordsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @owner = create :user, plan: "medium", login: "owner"
    @forker  = create :user, plan: "medium", login: "forker"

    @source = create :repository, owner: @owner, from_example: :pull_request_source
    @fork, msg = @source.fork(forker: @forker)
    assert @fork, "forking #{@source.inspect} as #{@forker.inspect} failed: #{msg.inspect}"

    @issue = create(:issue,
      user: @owner,
      repository: @source,
      body: "Everything is broken",
    )

    example_repo :pull_request_fork,   @fork

    @pull =
      PullRequest.create(
        repository: @source,
        base_repository: @source,
        base_user: @owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @forker,
        head_ref: "topic",
        issue: @issue,
        user: @forkerm,
    )

    refute_nil @pull.issue
    @issue.pull_request = @pull

    # Initiate Repository deletion
    @source.remove(@owner)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "can destroy issues while a PR also exists" do
    assert_difference("Issue.count", -1) do
      assert_difference("PullRequest.count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          DestroyDependentRecordsJob.perform_later("Repository", @source.id, :issues)
        end
      end
    end
  end

  test "expected queries" do
    issue2 = create(:issue, user: @owner, repository: @source, body: "Everything is still broken")

    exist_pattern = /\ASELECT `repositories`.* FROM `repositories` WHERE `repositories`.`id` = #{@source.id} LIMIT 1/
    ids_pattern = /\ASELECT id FROM issues WHERE repository_id = '#{@source.id}' AND id > '0' ORDER BY id LIMIT 100/
    select_pattern = /\ASELECT `issues`.* FROM `issues` WHERE `issues`.`id` IN \(#{@issue.id}, #{issue2.id}\)/
    delete_pattern = /\ADELETE FROM `issues` WHERE `issues`.`id` = (#{@issue.id}|#{issue2.id})/

    # When events_v2_publish_issues_deleted_tier1_event is enabled, we call generate_deleted_tier1_event for issue delete
    # which get the global_ids by calling Event::Domain global_ids that cache the repository so we make one less query
    # In enterprise mode, global_ids returns static values
    expected_exist_pattern_count = TestEnv.enterprise? || !GitHub.flipper[:events_v2_publish_issues_deleted_tier1_event].enabled? ? 4 : 3

    assert_queries_matching(exist_pattern, expected_exist_pattern_count) do
      assert_queries_matching(ids_pattern, 1) do
        assert_queries_matching(select_pattern, 1) do
          assert_queries_matching(delete_pattern, 2) do
            perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
              if TestEnv.test_all_features?
                DestroyDependentRecordsJob.perform_later("Issue", @source.id, :repository, inverse_relationship: true)
              else
                DestroyDependentRecordsJob.perform_later("Repository", @source.id, :issues)
              end
            end
          end
        end
      end
    end
  end

  test "destroys multiple associated instances with a cross-table shard query exemption" do
    user = create(:user)
    repo = create(:repository, owner: user)
    create(:check_suite, repository: repo)
    create(:check_suite, repository: repo)
    # Initiate Repository deletion
    repo.remove(user)

    assert_difference("CheckSuite.where(repository_id: #{repo.id}).count", -2) do
      DestroyDependentRecordsJob.perform_now("Repository", repo.id, :check_suites, cross_shard_query_exempted: true)
    end
  end

  test "destroys multiple associated instances without a cross-table shard query exemption" do
    user = create(:user)
    repo = create(:repository, owner: user)
    create(:check_suite, repository: repo)
    create(:check_suite, repository: repo)
    # Initiate Repository deletion
    repo.remove(user)

    assert_difference("CheckSuite.where(repository_id: #{repo.id}).count", -2) do
      DestroyDependentRecordsJob.perform_now("Repository", repo.id, :check_suites, sharding_key: :repository_id, sharding_value: repo.id, cross_shard_query_exempted: false)
    end
  end

  test "expected queries for multiple associated instances without a cross-table shard query exemption" do
    user = create(:user)
    repo = create(:repository, owner: user)
    check1 = create(:check_suite, repository: repo)
    check2 = create(:check_suite, repository: repo)
    # Initiate Repository deletion
    repo.remove(user)

    exist_pattern = /\ASELECT `repositories`.* FROM `repositories` WHERE `repositories`.`id` = #{repo.id} LIMIT 1/
    ids_pattern = /\ASELECT id FROM check_suites WHERE repository_id = '#{repo.id}' AND id > '0' AND repository_id = '#{repo.id}' ORDER BY id LIMIT 100/
    select_pattern = /\ASELECT `check_suites`.`id`, .+ FROM `check_suites` WHERE `check_suites`.`id` IN \(#{check1.id}, #{check2.id}\) AND `check_suites`.`repository_id` = #{repo.id}/
    delete_pattern = /\ADELETE FROM `check_suites` WHERE `check_suites`.`id` = (#{check1.id}|#{check2.id})/

    assert_queries_matching(exist_pattern, 1) do
      assert_queries_matching(ids_pattern, 1) do
        assert_queries_matching(select_pattern, 1) do
          assert_queries_matching(delete_pattern, 2) do
            if TestEnv.test_all_features?
              DestroyDependentRecordsJob.perform_now("CheckSuite", repo.id, :repository,
                sharding_key: :repository_id,
                sharding_value: repo.id,
                cross_shard_query_exempted: false,
                inverse_relationship: true,
              )
            else
              DestroyDependentRecordsJob.perform_now("Repository", repo.id, :check_suites,
                sharding_key: :repository_id,
                sharding_value: repo.id,
                cross_shard_query_exempted: false,
              )
            end
          end
        end
      end
    end
  end

  test "can split work into batches" do
    3.times { create(:hook, installation_target: @source) }

    BatchedJob.stub_const(:BATCH_SIZE, 2) do
      assert_difference("Hook.count", -3) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          DestroyDependentRecordsJob.perform_later("Repository", @source.id, :hooks)
        end
      end
    end

    assert_equal 2, GitHub.dogstats.counts("batched_job.batch_size").length, "Expected 2 batches"
    assert_equal 3, GitHub.dogstats.counts("batched_job.batch_size").sum(&:value), "Expected 3 total records to be destroyed"
  end

  test "bails if a Repository record has been restored" do
    Failbot.expects(:report).with(instance_of(DestroyDependentRecordsJob::DestroyDependentRecordsError)).once

    @source.unhide
    assert_difference("Issue.count", 0) do
      assert_difference("PullRequest.count", 0) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          DestroyDependentRecordsJob.perform_later("Repository", @source.id, :issues)
        end
      end
    end
  end

  test "scopes deletions for polymorphic associations" do
    # create an organization and repo with same user id
    # orgs coexist with users, so find or create repo with the org's id, not a
    # an org with a repo's id (since a user with that id could exist)
    org = create(:organization)
    repo = Repository.find_by_id(org.id)
    if !repo
      repo = create(:repository, owner: org)
      repo.update_column(:id, org.id)
    end

    repo_hook = create(:hook, installation_target: repo)
    org_hook = create(:hook, :org, installation_target: org)

    repo.delete

    assert_equal 1, org.hooks.count
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      DestroyDependentRecordsJob.perform_later("Repository", repo.id, :hooks)
    end
    assert_equal 0, repo.repo_hook_associations_ff? ? Hook.hooks_for_target(repo).count : repo.hooks.count, "repo hook should have been deleted"
    assert_equal 1, org.hooks.count, "org hook should not have been deleted"
  end

  test "scopes deletions for polymorphic enum associations" do
    class ::TestRepository < Repository
      has_many :profile_pins, as: :pinned_item, dependent: :destroy
    end

    profile = create(:profile, user: @owner)
    repo = create(:repository, owner: @owner)
    pin = create(:profile_pin, pinned_item: repo, profile: profile)
    repo.delete

    assert_equal 1, ProfilePin.where(pinned_item: repo).count
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      DestroyDependentRecordsJob.perform_now("TestRepository", repo.id, :profile_pins, polymorphic_type_value: ProfilePin.pinned_item_types["Repository"])
    end
    assert_equal 0, ProfilePin.where(pinned_item: repo).count, "repo profile pin should have been deleted"
  end

  test "expected queries for polymorphic associations with default relationship" do
    class ::TestRepository < Repository
      has_many :profile_pins, as: :pinned_item, dependent: :destroy
    end
    profile = create(:profile, user: @owner)
    repo = create(:repository, owner: @owner)
    pin = create(:profile_pin, pinned_item: repo, profile: profile)
    repo.delete

    assert_equal 1, ProfilePin.where(pinned_item: repo).count

    exist_pattern = /\ASELECT `repositories`.* FROM `repositories` WHERE `repositories`.`id` = #{repo.id} LIMIT 1/
    ids_pattern = /\ASELECT id FROM profile_pins WHERE pinned_item_id = '#{repo.id}' AND id > '0' AND pinned_item_type = '0' ORDER BY id LIMIT 100/
    select_pattern = /\ASELECT `profile_pins`.* FROM `profile_pins` WHERE `profile_pins`.`id` = #{pin.id}/
    delete_pattern = /\ADELETE FROM `profile_pins` WHERE `profile_pins`.`id` = (#{pin.id})/

    assert_queries_matching(exist_pattern, 1) do
      assert_queries_matching(ids_pattern, 1) do
        assert_queries_matching(select_pattern, 1) do
          assert_queries_matching(delete_pattern, 1) do
            if TestEnv.test_all_features?
              DestroyDependentRecordsJob.perform_now("ProfilePin", repo.id, :pinned_item,
                polymorphic_type_value: ProfilePin.pinned_item_types["Repository"],
                inverse_relationship: true
              )
            else
              DestroyDependentRecordsJob.perform_now("TestRepository", repo.id, :profile_pins,
                polymorphic_type_value: ProfilePin.pinned_item_types["Repository"]
              )
            end
          end
        end
      end
    end
  end

  test "retries the job if a throttling error occurs" do
    assert_retry_on_throttler_error job: DestroyDependentRecordsJob, args: ["Repository", @source.id, :issues]
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: DestroyDependentRecordsJob, args: ["Repository", @source.id, :issues]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: DestroyDependentRecordsJob, args: ["Repository", @source.id, :issues]
  end

  test "retries some expected error classes" do
    [
      ActiveRecord::AdapterTimeout,
      ActiveRecord::ConnectionFailed,
      ActiveRecord::ConnectionNotEstablished,
    ].each do |error|
      assert_retry_on_error(
        error,
        DestroyDependentRecordsJob,
        ["Repository", @source.id, :issues]
      )
    end
  end

  test "retries on Freno::Throttler::WaitedTooLong" do
    args = ["Repository", @source.id, :issues]
    DestroyDependentRecordsJob.any_instance.stubs(:perform).raises(Freno::Throttler::WaitedTooLong)

    assert_enqueued_with(job: DestroyDependentRecordsJob, args: args) do
      DestroyDependentRecordsJob.perform_now(*args)
    end
  end

  test "ablility to delete models in different database clusters" do
    post = create(:discussion_post)
    reaction = Reaction.react(
      user: post.user,
      subject_id: post.id,
      subject_type: post.class.name,
      content: "+1")

    args = ["DiscussionPost", post.id, :reactions]

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      DestroyDependentRecordsJob.perform_later(*args)
    end
  end

  test "increments destroy_dependent_records dogstats" do
    original_issues = create_list(:issue, 2, repository: @source)
    expected_stats_tags = [
      "parent_model:repository",
      "parent_model_catalog_service:github/#{GitHub.enterprise? ? "unknown" : "apps"}", # apps is incorrect but it's a limitation of the service resolution used in tests
      "association:#{TestEnv.test_all_features? ? "repository" : "issues"}",
      "table_model:issue",
      "table_model_catalog_service:github/#{GitHub.enterprise? ? "unknown" : "issues"}",
      "queue:background_destroy_issues_pull_requests",
      "cluster:issues-pull-requests",
      "inverse_relationship:#{!!TestEnv.test_all_features?}",
      "cross_shard_query_exempted:false",
    ].freeze

    assert_difference("Issue.count", -3) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        if TestEnv.test_all_features?
          DestroyDependentRecordsJob.perform_later("Issue", @source.id, :repository, inverse_relationship: true)
        else
          DestroyDependentRecordsJob.perform_later("Repository", @source.id, :issues)
        end
      end
    end

    assert_equal(
      1,
      GitHub.dogstats.increments("destroy_dependent_records", tags: expected_stats_tags).length
    )

    assert_equal(
      3,
      GitHub.dogstats.counts("destroy_dependent_records.records_destroyed", tags: expected_stats_tags).last.value
    )
  end

  test "increments destroy_dependent_records.records_not_destroyed dogstats if destroy fails" do
    expected_stats_tags = [
      "parent_model:milestone",
      "parent_model_catalog_service:github/#{GitHub.enterprise? ? "unknown" : "issues"}",
      "association:#{TestEnv.test_all_features? ? "milestone" : "issues"}",
      "table_model:issue",
      "table_model_catalog_service:github/#{GitHub.enterprise? ? "unknown" : "issues"}",
      "queue:background_destroy_issues_pull_requests",
      "cluster:issues-pull-requests",
      "inverse_relationship:#{!!TestEnv.test_all_features?}",
      "cross_shard_query_exempted:false",
    ].freeze
    milestone = create(:milestone)
    create(:issue, repository: milestone.repository, milestone: milestone)

    Issue.any_instance.stubs(:destroy).returns(false)

    assert_no_difference("Issue.count") do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        if TestEnv.test_all_features?
          DestroyDependentRecordsJob.perform_later("Issue", milestone.id, :milestone, inverse_relationship: true)
        else
          DestroyDependentRecordsJob.perform_later("Milestone", milestone.id, :issues)
        end
      end
    end

    assert_equal(
      1,
      GitHub.dogstats.counts("destroy_dependent_records.records_not_destroyed", tags: expected_stats_tags).last.value
    )
  end

  test "logs if a record could not be destroyed" do
    milestone = create(:milestone)
    issue = create(:issue, repository: milestone.repository, milestone: milestone)

    Issue.any_instance.stubs(:destroy).returns(false)
    errors = stub(full_messages: ["Something weird happened"])
    Issue.any_instance.stubs(:errors).returns(errors)

    GitHub.logger.expects(:warn).once.with(
      "Dependent record failed to be destroyed", {
        "code.namespace" => "DestroyDependentRecordsJob",
        "code.function" => "process_batch",
        "table_model" => "Issue",
        "table_model_id" => issue.id,
        "parent_model" => "Milestone",
        "parent_model_id" => milestone.id,
        "error" => "Something weird happened"
      }
    )

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      DestroyDependentRecordsJob.perform_later("Milestone", milestone.id, :issues)
    end
  end

  context ".custom_queue_name" do
    test "uses dedicated queue when set" do
      ApplicationRecord::IssuesPullRequests.stub(:dedicated_background_destroy_queue_name, :background_destroy_issues_pull_requests) do
        job = DestroyDependentRecordsJob.perform_later("Repository", @source.id, :issues)
        assert_equal "background_destroy_issues_pull_requests", job.queue_name
      end
    end

    test "uses default queue when not set" do
      ApplicationRecord::IssuesPullRequests.stub(:dedicated_background_destroy_queue_name, nil) do
        job = DestroyDependentRecordsJob.perform_later("Repository", @source.id, :issues)
        assert_equal "background_destroy", job.queue_name
      end
    end

    test "does not raise with no arguements" do
      assert_equal "background_destroy", DestroyDependentRecordsJob.new.queue_name
    end
  end
end
