# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ResyncMemexProjectItemsIndexJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include MemexHelpers

  # The default number of retry attempts we get from ActiveJob.retry_on
  DEFAULT_RETRY_ATTEMPTS = 5

  FIXED_SESSION_ID = SecureRandom.uuid
  class FixedSessionId
    def self.value
      @session_id
    end

    def self.generate
      @session_id = SecureRandom.uuid
    end
  end

  class WithFixedSession < ResyncMemexProjectItemsIndexJob
    def generate_session_id
      FixedSessionId.value
    end
  end

  class WithLockStealing < ResyncMemexProjectItemsIndexJob
    def can_steal_lock?
      true
    end
  end

  class ArgumentsLogger
    def self.add(value)
      values << value
    end

    def self.values
      @values ||= []
    end

    def self.clear
      self.values.clear
    end
  end

  class FailsOnce < ResyncMemexProjectItemsIndexJob
    def perform(*arguments, **options)
      ArgumentsLogger.add(self.arguments)
      if ArgumentsLogger.values.length == 1
        raise Resiliency::Response::UnavailableError
      end
    end
  end

  fixtures do
    @beginning_of_week = Time.zone.now.beginning_of_week.freeze

    @project, @unrelated_project = create_list(:memex_project, 2)
    create_list(:memex_project_item, 5, memex_project: @project, created_at: @beginning_of_week, updated_at: @beginning_of_week)
    create_list(:memex_project_item, 5, memex_project: @unrelated_project, created_at: @beginning_of_week, updated_at: @beginning_of_week)
  end

  setup do
    FixedSessionId.generate
    ArgumentsLogger.clear
    reset_monolith_redis_rate_limiter
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
    @document_type = Elastomer::Adapters::MemexProjectItem.document_type
    GitHub.flipper[:memex_reconciler_read_only].disable
  end

  teardown_once do
    teardown_search
  end

  private def perform_batched_job!(wait_for_refresh: true, batch_size: 2, bypass_rate_limit: true, read_only: false)
    status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)
    assert_predicate status, :pending?

    RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false) if bypass_rate_limit

    ResyncMemexProjectItemsIndexJob.stub_const(:BATCH_SIZE, batch_size) do
      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        ResyncMemexProjectItemsIndexJob.perform_later(@project.id, status.id, wait_for_refresh:, read_only:)
      end
    end

    assert_predicate ResyncMemexProjectItemsIndexJobStatus.find!(status.id), :success?
    status.id
  end

  private def enqueue_job!(job_status = nil, with_fixed_session: false, with_lock_stealing: false, fail_once: false, rate_at_limit: false)
    status = job_status || ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

    RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(rate_at_limit)

    if with_lock_stealing
      WithLockStealing.perform_later(@project.id, status.id)
    elsif fail_once
      FailsOnce.perform_later(@project.id, status.id)
    elsif with_fixed_session
      WithFixedSession.perform_later(@project.id, status.id)
    else
      ResyncMemexProjectItemsIndexJob.perform_later(@project.id, status.id)
    end
  end

  private def count_elasticsearch_documents(project)
    @index.count(
      {
        query: {
          bool: {
            filter: {
              term: {
                memex_project_id: {
                  value: project.id
                }
              }
            }
          }
        }
      },
      routing: project.id,
      type: @document_type
    )
  end

  context "#perform" do
    test "syncs all of a single project's items to Elasticsearch" do
      refute_empty @project.memex_project_items
      refute_empty @unrelated_project.memex_project_items
      assert_equal 0, count_elasticsearch_documents(@project)
      assert_equal 0, count_elasticsearch_documents(@unrelated_project)

      status_id = perform_batched_job!
      status = ResyncMemexProjectItemsIndexJobStatus.find!(status_id)

      # Make sure we synced all the items.
      assert_equal @project.memex_project_items.length, count_elasticsearch_documents(@project)
      assert_equal 0, count_elasticsearch_documents(@unrelated_project)

      # Make sure the job status is accurate.
      assert_equal @project.id, status.context[:memex_project_id]
      refute_nil status.context[:started_at]
      assert_equal @project.memex_project_items.length, status.context[:reconciled_items]
      assert_equal @project.memex_project_items.length, status.context[:total_items]
    end

    test "removes stale items from Elasticsearch when necessary" do
      original_item_count = @project.memex_project_items.length
      assert original_item_count > 0

      # Sync all the items to Elasticsearch for the first time.
      perform_batched_job!

      assert_equal @project.memex_project_items.length, count_elasticsearch_documents(@project)

      # Delete the last item
      @project.memex_project_items.last.destroy!
      @project.memex_project_items.reload

      # Re-run the job.
      status_id = perform_batched_job!
      status = ResyncMemexProjectItemsIndexJobStatus.find!(status_id)

      # Make sure we removed the last item.
      assert_equal original_item_count - 1, count_elasticsearch_documents(@project)

      # Make sure the job status is accurate.
      assert_equal @project.id, status.context[:memex_project_id]
      refute_nil status.context[:started_at]
      assert_equal 1, status.context[:reconciled_items]
      assert_equal original_item_count, status.context[:total_items]
    end

    test "clears all of a project's items from Elasticsearch when the project is empty" do
      # Sync all the items to Elasticsearch for the first time.
      original_item_count = @project.memex_project_items.length
      assert original_item_count > 0
      perform_batched_job!
      assert_equal @project.memex_project_items.length, count_elasticsearch_documents(@project)

      # Delete all the items.
      @project.memex_project_items.destroy_all

      # Re-run the job without any items.
      status_id = perform_batched_job!
      status = ResyncMemexProjectItemsIndexJobStatus.find!(status_id)

      # Make sure we cleared all the items that we synced to Elasticsearch initially.
      assert_equal 0, count_elasticsearch_documents(@project)

      # Make sure the job status is accurate.
      assert_equal @project.id, status.context[:memex_project_id]
      refute_nil status.context[:started_at]
      assert_equal original_item_count, status.context[:reconciled_items]
      assert_equal original_item_count, status.context[:total_items]
    end

    test "records an error on the job status object after exhausting retries from dirty exits" do
      ResyncMemexProjectItemsIndexJob
        .any_instance
        .stubs(:perform)
        .raises(Aqueduct::Worker::JobKilled, "job was killed")

      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_performed_jobs(DEFAULT_RETRY_ATTEMPTS, only: ResyncMemexProjectItemsIndexJob) do
        perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
          enqueue_job!(job_status)
        end
      end

      assert_predicate ResyncMemexProjectItemsIndexJobStatus.find!(job_status.id), :error?
      assert_equal "job was killed", Failbot.exception_message_from_hash(Failbot.reports.last)
    end

    test "records an error on the job status object after exhausting retires from replication lag" do
      GitHub.flipper[:active_job_default_to_write_connection].disable

      Freno.client.stubs(:replication_delay).returns(SmartDatabaseSelection::MAX_REPLICATION_DELAY_WAIT_SECONDS + 1)

      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_performed_jobs(DEFAULT_RETRY_ATTEMPTS, only: ResyncMemexProjectItemsIndexJob) do
        perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
          enqueue_job!(job_status)
        end
      end

      assert_predicate ResyncMemexProjectItemsIndexJobStatus.find!(job_status.id), :error?
      assert_match /Cannot wait (\d|\.)+ seconds for replication/, Failbot.exception_message_from_hash(Failbot.reports.last)
    end

    test "records an error on the job status object after exhausting retries from recoverable errors" do
      ResyncMemexProjectItemsIndexJob
        .any_instance
        .stubs(:perform)
        .raises(Resiliency::Response::UnavailableExceptions.first, "recoverable error")

      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_performed_jobs(DEFAULT_RETRY_ATTEMPTS, only: ResyncMemexProjectItemsIndexJob) do
        perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
          enqueue_job!(job_status)
        end
      end

      assert_predicate ResyncMemexProjectItemsIndexJobStatus.find!(job_status.id), :error?
      assert_equal "recoverable error", Failbot.exception_message_from_hash(Failbot.reports.last)
    end

    test "can enqueue unrelated projects" do
      assert_no_enqueued_jobs

      RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)
      ResyncMemexProjectItemsIndexJob.perform_later(@project.id, ResyncMemexProjectItemsIndexJobStatus.create(@project.id).id)
      ResyncMemexProjectItemsIndexJob.perform_later(@unrelated_project.id, ResyncMemexProjectItemsIndexJobStatus.create(@unrelated_project.id).id)

      assert_enqueued_jobs 2
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.skipped.count")
    end

    test "accepts an option to enable the flag for the project" do
      assert_no_enqueued_jobs
      to_flag_in = create(:memex_project)
      GitHub.flipper[:memex_table_without_limits].disable(to_flag_in)
      refute GitHub.flipper[:memex_table_without_limits].enabled?(to_flag_in)

      status = ResyncMemexProjectItemsIndexJobStatus.create(to_flag_in.id)
      RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)
      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        ResyncMemexProjectItemsIndexJob.perform_later(to_flag_in.id, status.id, enable_beta_flag: true)
      end

      assert GitHub.flipper[:memex_table_without_limits].enabled?(to_flag_in)
    end

    test "doesn't enqueue double batches" do
      assert_no_enqueued_jobs

      enqueue_job!
      enqueue_job!  # try to enqueue the same project

      assert_enqueued_jobs 1
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(1, "resync_memex_project_items_index_job.skipped.count")
    end

    test "doesn't enqueue new jobs that would take us over the rate limit" do
      assert_no_enqueued_jobs

      enqueue_job!
      2.times.each { enqueue_job!(rate_at_limit: true) }

      assert_enqueued_jobs 1
      assert_dogstats_increment(2, "rate_limiting.limited_request", tags: ["source:resync_memex_project_items_index_job"])
    end

    test "doesn't rate limit continuation jobs" do
      batch_size = 1
      num_batches = (@project.memex_project_items.length.to_f / batch_size).ceil

      # Make sure that we will attempt to process more jobs than are allowed by the rate limit.
      assert num_batches > ResyncMemexProjectItemsIndexJob::DEFAULT_RATE_LIMIT_OPTIONS[:max_tries]

      perform_batched_job!(batch_size: batch_size, bypass_rate_limit: false)

      refute_dogstats_increment("rate_limiting.limited_request", tags: ["source:resync_memex_project_items_index_job"])
    end

    test "logs info from rate limit helper method" do
      assert_logged(
          "Body" => "Checking whether or not to apply rate limit",
          "code.namespace" => "ResyncMemexProjectItemsIndexJob",
          "code.function" => "first_job?",
          "gh.memex.project.id" => @project.id,
      ) do
        perform_batched_job!(bypass_rate_limit: false)
      end
    end

    test "Allows double batch after timeout" do
      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_no_enqueued_jobs

      enqueue_job!(job_status)
      travel_to(5.minutes.from_now) do
        enqueue_job!(job_status)
      end

      assert_enqueued_jobs 2
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.skipped.count")
    end

    test "Enqueing with same session_id is allowed" do
      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_no_enqueued_jobs

      # As part of a batch job run, another job will be enqueued before the current one finished.
      # This job will have different offset_id and progress but the same session_id.
      enqueue_job!(job_status, with_fixed_session: true)
      enqueue_job!(job_status, with_fixed_session: true)

      assert_enqueued_jobs 2
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.skipped.count")
    end

    test "Enqueue refreshes lock" do
      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_no_enqueued_jobs

      enqueue_job!(job_status, with_fixed_session: true)
      travel_to(5.minutes.from_now) do
        enqueue_job!(job_status, with_fixed_session: true)

        FixedSessionId.generate
        enqueue_job!(job_status, with_fixed_session: true)
      end

      assert_enqueued_jobs 2
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(1, "resync_memex_project_items_index_job.skipped.count")
    end

    test "Can steal lock" do
      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_no_enqueued_jobs

      enqueue_job!(job_status, with_lock_stealing: true)
      enqueue_job!(job_status, with_lock_stealing: true)

      assert_enqueued_jobs 2
      assert_dogstats_increment(1, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.skipped.count")
    end

    test "Unlocks after failing retries" do
      ResyncMemexProjectItemsIndexJob
        .any_instance
        .stubs(:perform)
        .raises(Resiliency::Response::UnavailableExceptions.first, "recoverable error")

      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        enqueue_job!(job_status)
      end

      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_no_enqueued_jobs

      enqueue_job!(job_status)

      assert_enqueued_jobs 1
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.interrupted.count")
      assert_dogstats_increment(0, "resync_memex_project_items_index_job.skipped.count")
    end

    test "Reuses session after fail" do
      job_status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      assert_performed_jobs(2, only: FailsOnce) do
        perform_enqueued_jobs only: FailsOnce do
          enqueue_job!(job_status, fail_once: true)
        end
      end

      assert_equal ArgumentsLogger.values[0], ArgumentsLogger.values[1]
    end

    test "Records an error on the job status object when job is skipped" do
      job_status_should_pending = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)
      job_status_should_error = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)

      kv_helper = ResyncMemexProjectItemsIndexJob::KvHelper.new(ResyncMemexProjectItemsIndexJob, @project.id)

      enqueue_job!(job_status_should_pending)
      session_id = kv_helper.session_lock
      refute_nil session_id
      job_status_should_pending = ResyncMemexProjectItemsIndexJobStatus.find!(job_status_should_pending.id)

      enqueue_job!(job_status_should_error)
      should_be_unchanged_session_id = kv_helper.session_lock
      job_status_should_error = ResyncMemexProjectItemsIndexJobStatus.find!(job_status_should_error.id)


      assert_predicate job_status_should_pending, :pending?
      assert_predicate job_status_should_error, :error?
      assert_equal "Job skipped because conflicting job is already running", job_status_should_error.error_message
      assert_equal session_id, should_be_unchanged_session_id
    end

    test "traces its execution" do
      refute_empty @project.memex_project_items

      perform_batched_job!

      assert_equal @project.memex_project_items.length, count_elasticsearch_documents(@project)

      span = find_span_by(name: "resync_memex_project_items_index_job#perform")
      refute_nil span

      # Although  more attributes will typically be present, verify just the basic ones.
      assert_equal 4, span.attributes["gh.memex.job.progress"]
      assert_equal true, span.attributes["gh.memex.resync_memex_project_items_index_job.wait_for_refresh"]
      refute_nil span.attributes["gh.memex.job.initial_start"]
      assert_equal @project.id, span.attributes["gh.memex.project.id"]
      refute_nil span.attributes["gh.job_status.id"]
      refute_nil span.attributes["gh.memex.job.offset_item.id"]
      refute_nil span.attributes["gh.memex.job.session.id"]
    end

    test "runs to successful completion when we aren't waiting for newly written data to become searchable" do
      refute_empty @project.memex_project_items

      perform_batched_job!(wait_for_refresh: false)

      span = find_span_by(name: "resync_memex_project_items_index_job#perform")
      refute_nil span

      assert_equal @project.id, span.attributes["gh.memex.project.id"]
      refute span.attributes["gh.memex.resync_memex_project_items_index_job.wait_for_refresh"]
    end

    test "stores consistency score" do
      refute_empty @project.memex_project_items
      perform_batched_job!
      consistency_record = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @project.id)
      assert T.must(consistency_record.repair_started_at) < consistency_record.evaluated_at
      assert T.must(consistency_record.evaluated_at) < consistency_record.repair_finished_at
      assert_equal 0.0, consistency_record.consistency
    end

    test "calculates consistency score correctly" do
      refute_empty @project.memex_project_items
      # Populate the index with all but 1 item so that this 1 item will be reported as inconsistent
      populate_elasticsearch_index!(@project.memex_project_items[1..])
      perform_batched_job!(batch_size: @project.memex_project_items.length)

      expected_consistency_score = 1 - (
        # 1 item out of all items is inconsistent
        1.0 / @project.memex_project_items.length.to_f
      )
      actual_consistency_score = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @project.id).consistency
      assert_equal expected_consistency_score, actual_consistency_score
    end

    test "on exception, updates repair_started_at but leaves all other attributes untouched" do
      seed_time = Time.current.beginning_of_day
      attrs = { consistency: 0.5, repair_started_at: seed_time, repair_finished_at: seed_time, evaluated_at: seed_time }
      MemexProjectElasticsearchConsistency.create_or_update(@project.id, **attrs)
      Search::MemexProjectItemReconciler.any_instance.expects(:reconcile!).raises(StandardError)

      status = ResyncMemexProjectItemsIndexJobStatus.create(@project.id)
      perform_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
        # We can only catch the exception properly if we rescue from within the perform_enqueued_jobs block
        assert_raises(StandardError) do
          ResyncMemexProjectItemsIndexJob.perform_later(@project.id, status.id)
        end
      end

      consistency_record = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @project.id)
      assert_equal attrs[:consistency], consistency_record.consistency
      assert_same_time attrs[:evaluated_at], consistency_record.evaluated_at
      assert_same_time attrs[:repair_finished_at], consistency_record.repair_finished_at
      assert attrs[:repair_started_at] < consistency_record.repair_started_at
    end

    test "does not update repair timestamps when read-only is true" do
      perform_batched_job!(read_only: true)
      consistency_record = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @project.id)
      assert consistency_record.evaluated_at
      assert consistency_record.consistency
      refute consistency_record.repair_started_at
      refute consistency_record.repair_finished_at
    end

    test "resolves tenant context", skip_enterprise: true do
      tenant_admin = create(:emu)
      tenant = tenant_admin.enterprise_managed_business
      tenant_org = create(:organization, business: tenant)
      memex_project = create(:memex_project, owner: tenant_org).tap { |p| p.grant_role(tenant_admin, :writer) }

      status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
      RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)

      on_multi_tenant_enterprise do
        assert_nil GitHub::CurrentTenant.get

        ResyncMemexProjectItemsIndexJob.perform_now(memex_project.id, status.id)

        assert_equal GitHub::CurrentTenant.get.id, tenant.id
      end
    end
  end
end
