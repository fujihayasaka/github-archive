# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkReposIndexJobTest < GitHub::TestCase
  setup do
    create_search_indices
    setup_search

    @orgs = create_list :enterprise_linked_organization, 3
    @org = @orgs.first
    @biz = @org.business
    @repos_map = @orgs.index_with { |org| create_list :repository, 3, owner: org }
    @first_repo = @repos_map[@org].first

    GitHub.flipper[:skip_bulk_repos_index_job].disable
  end

  teardown do
    teardown_search
  end

  test "reindexes all repos for an org" do
    assert_enqueued_jobs 1, only: BulkReposIndexJob do
      BulkReposIndexJob.reindex_org(@org.id)
    end
  end

  test "reindexes all repos for an enterprise" do
    assert_enqueued_jobs 1, only: BulkReposIndexJob do
      BulkReposIndexJob.reindex_business(@biz)
    end
  end

  test "enqueues more jobs for larger orgs" do
    largish_org = create :organization
    create_list :repository, 10, owner: largish_org
    BulkReposIndexJob.stub_const(:LIMIT, 3) do
      # 10 repos in batches of 3 will require 4 jobs
      assert_enqueued_jobs 4, only: BulkReposIndexJob do
        BulkReposIndexJob.reindex_org(largish_org.id)
      end

      # only 1 job required for 3 repos
      assert_enqueued_jobs 1, only: BulkReposIndexJob do
        BulkReposIndexJob.reindex_org(@org.id)
      end
    end
  end

  test "do not enqueue job if org is skipped" do
    largish_org = create :organization
    create_list :repository, 10, owner: largish_org
    GitHub.flipper[:skip_bulk_repos_index_job].enable(largish_org)
    assert_query_count(0, ignore_feature_flags: true) do
      assert_no_enqueued_jobs only: BulkReposIndexJob do
        BulkReposIndexJob.reindex_org(largish_org.id)
      end
    end
    GitHub.flipper[:skip_bulk_repos_index_job].disable(largish_org)
    assert_enqueued_jobs 1, only: BulkReposIndexJob do
      BulkReposIndexJob.reindex_org(largish_org.id)
    end
  end

  test "only query definitions once for all repos" do
    # It wouldn't query custom_property_values if there are no definitions
    create :custom_property_definition, source: @org, property_name: "env"

    assert_query_count_per_table({
      custom_property_definitions: 2,
      custom_property_values: 1,
      internal_repositories: 1,
      mirrors: 1,
      repository_networks: 1,
      repository_sponsorables: GitHub.enterprise? ? 0 : 1,
      repository_topics: 1,
      users: 1,
    }) do
      perform_enqueued_jobs only: BulkReposIndexJob do
        BulkReposIndexJob.reindex_org(@org.id)
      end
    end
  end

  test "enqueues a job for each writable index" do
    secondary_config = Elastomer::Router::IndexConfig.new(name: "#{repos_index_name}-2", cluster: "default", version: "any-sha", primary: false, read: true, write: true)
    Elastomer.router.update_index_config(secondary_config)
    Elastomer.router.index_map.refresh

    assert_enqueued_jobs 2, only: BulkReposIndexJob do
      jobs = BulkReposIndexJob.reindex_org(@org.id)
      assert_equal 2, jobs.size
    end
  end

  test "enqueues a separate job for each org requested" do
    assert_enqueued_jobs 3, only: BulkReposIndexJob do
      jobs = @orgs.flat_map { |org| BulkReposIndexJob.reindex_org(org.id) }
      expected_group_keys = @orgs.map { |org| "BulkReposIndexJob/#{repos_index_name}/org:[#{org.id}]" }
      assert_equal expected_group_keys, jobs.map(&:group_key)
    end
  end

  test "enqueues a single job for all orgs in the provided enterprise" do
    assert_enqueued_jobs 1, only: BulkReposIndexJob do
      jobs = BulkReposIndexJob.reindex_business(@biz)
      org_ids = @biz.organizations.ids.join(", ")
      assert_equal ["BulkReposIndexJob/#{repos_index_name}/org:[#{org_ids}]"], jobs.map(&:group_key)
    end
  end

  test "uses a common group key if the same org is indexed again" do
    assert_enqueued_jobs 3, only: BulkReposIndexJob do
      jobs = 3.times.flat_map { BulkReposIndexJob.reindex_org(@org.id) }
      expected_group_keys = Array.new(3, "BulkReposIndexJob/#{repos_index_name}/org:[#{@org.id}]")
      assert_equal expected_group_keys, jobs.map(&:group_key)
    end
  end

  def repos_index_name
    "repos#{Elastomer::Environment.postfix}"
  end
end
