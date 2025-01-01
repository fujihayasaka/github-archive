# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class RepairMemexProjectItemsIndexJobTest < GitHub::TestCase
  include MemexHelpers

  # Takes in a Elastomer::Interfaces::Document::MemexProjectItem::Value
  # Recursively stringifies all hash keys
  def deep_stringify(value)
    if value.is_a?(Array)
      value.map { |v| deep_stringify(v) }
    elsif value.is_a?(Hash)
      value.deep_stringify_keys!
    else
      value
    end
  end

  fixtures do
    @organization = create(:organization)
    @user = create(:verified_user).tap { |user| @organization.add_member(user) }
    @memex_project_without_limits = create(:memex_project, owner: @organization, creator: @user)
    @memex_project_with_limits = create(:memex_project, owner: @organization, creator: @user)
    @memex_project_without_limits_items = create_list(:memex_project_item, 10, memex_project: @memex_project_without_limits)
    @memex_project_with_limits_items = create_list(:memex_project_item, 5, memex_project: @memex_project_with_limits)
    @expected_item_count = @memex_project_without_limits_items.length + @memex_project_with_limits_items.length

    @document_type = Elastomer::Adapters::MemexProjectItem.document_type

    enable_feature_flag(:memex_table_without_limits, @memex_project_without_limits)
    disable_feature_flag(:memex_increased_issues_graph_timeouts)
  end

  setup do
    @index = Elastomer::Indexes::MemexProjectItems.new.freeze
    @cluster = Elastomer.router.cluster_for_index(@index.name)

    setup_search
  end

  teardown_once do
    teardown_search
  end

  test "raises errors to allow for retrying exceptions" do
    job = RepairMemexProjectItemsIndexJob.new(@index.name)
    reconciler = job.reconcilers.first

    assert_predicate job, :raise_errors?
    assert_predicate reconciler, :raise_errors
  end

  test "#to_partial_path" do
    job = RepairMemexProjectItemsIndexJob.new(@index.name)

    assert_equal "stafftools/search_indexes/repair_jobs/memex_project_items/repair_job", job.to_partial_path
  end

  context "#strategy" do
    test "defaults to All projects strategy" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)

      assert_equal RepairMemexProjectItemsIndexJob::Strategy::AllProjects, repair_job.strategy
    end

    test "can set to VisitedAfter strategy" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)
      repair_job.visited_after = 1.day.ago.to_date

      assert_equal RepairMemexProjectItemsIndexJob::Strategy::VisitedAfter, repair_job.strategy
    end
  end

  context "#visited_after" do
    test "does not return date if not set" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)

      assert_nil repair_job.visited_after, "Expected no visited after date"
    end

    test "returns stored visited_after date" do
      freeze_time

      visited_after = 1.day.ago.to_date
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)
      repair_job.visited_after = visited_after

      assert_equal visited_after, repair_job.visited_after, "Expected visited after date to be set"
    end
  end

  context "#visited_after=" do
    test "can set visited_after date" do
      freeze_time

      visited_after = 1.day.ago.to_date
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)
      repair_job.visited_after = visited_after

      assert_equal visited_after, repair_job.visited_after, "Expected visited after date to be set"
    end

    test "cannot set visited_after date into the future" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)

      assert_raises ArgumentError do
        repair_job.visited_after = 1.day.from_now.to_date
      end
    end

    test "clears visited_after stored date if set to nil" do
      freeze_time

      visited_after = 1.day.ago.to_date
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name).tap(&:reset!)
      repair_job.visited_after = visited_after

      assert_changes -> { repair_job.visited_after }, from: visited_after, to: nil do
        repair_job.visited_after = nil
      end
    end
  end

  context "perform" do
    test "completes reconciliation process" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      repair_job.enable

      MemexProjectItems::Reconciler.stub_const :MEMEX_PROJECT_BATCH_SIZE, 1 do
        assert_changes -> { repair_job.finished? }, from: false, to: true do
          assert_changes -> { repair_job.reconciler.memex_projects_reconciled_count }, from: 0, to: 2 do
            perform_enqueued_jobs only: RepairMemexProjectItemsIndexJob do
              repair_job.start 1
            end
          end
        end
      end

      # The job is re-enqueued until there is an empty set of models returned to mark it as finished,
      # number of projects + 1
      assert_performed_jobs 3, only: RepairMemexProjectItemsIndexJob
    end

    test "reconciliation process completes if batch fails" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      repair_job.enable
      reconciler = repair_job.reconciler

      total_document_count = lambda do
        @index.count_all({
          query: {
            match_all: {},
          },
        })
      end

      MemexProjectItems::Reconciler.any_instance.stubs(:reconcile_memex_project).raises(StandardError)

      MemexProjectItems::Reconciler.stub_const :MEMEX_PROJECT_BATCH_SIZE, 1 do
        assert_no_changes total_document_count, from: 0 do
          assert_changes -> { reconciler.failed_reconciler_batches_count }, from: 0, to: 2 do
            assert_changes -> { repair_job.finished? }, from: false, to: true do
              perform_enqueued_jobs only: RepairMemexProjectItemsIndexJob do
                repair_job.start 1
              end

              Elastomer::TestHelpers.index_refresh(@index.name)
            end
          end
        end
      end

      # Each project is enqueued for a total of 3 times, and the last batch is enqueued once to mark repair as
      # finished.
      assert_performed_jobs 7, only: RepairMemexProjectItemsIndexJob
    end
  end

  context "retry_on_dirty_exit" do
    test "retries on dirty exit" do
      job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      job.enable
      MemexProjectItems::Reconciler.any_instance.stubs(:reconcile).raises(Aqueduct::Worker::JobKilled)

      events = subscribed("enqueue_retry.active_job") do
        RepairMemexProjectItemsIndexJob.perform_now(@index.name, { cluster: @cluster })
      end

      assert_equal 1, events.size
      event = events.pop
      _, _, _, _, payload = event

      assert_kind_of Aqueduct::Worker::JobKilled, payload[:error]
    end
  end

  context "retry_on" do
    test "retries on StandardError" do
      job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      job.enable
      MemexProjectItems::Reconciler.any_instance.stubs(:reconcile_memex_project).raises(StandardError)

      events = subscribed("enqueue_retry.active_job") do
        perform_enqueued_jobs(only: RepairMemexProjectItemsIndexJob) do
          RepairMemexProjectItemsIndexJob.perform_later(@index.name, { cluster: @cluster })
        end
      end

      assert_equal 2, events.size
      event = events.pop
      _, _, _, _, payload = event

      assert_kind_of StandardError, payload[:error]
    end

    test "drops job after multiple errors" do
      job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      job.enable
      MemexProjectItems::Reconciler.any_instance.stubs(:reconcile_memex_project).raises(StandardError)

      events = subscribed("retry_stopped.active_job") do
        perform_enqueued_jobs(only: RepairMemexProjectItemsIndexJob) do
          RepairMemexProjectItemsIndexJob.perform_later(@index.name, { cluster: @cluster })
        end
      end

      assert_equal 1, events.size
      event = events.pop
      _, _, _, _, payload = event

      assert_kind_of StandardError, payload[:error]
    end
  end

  context "retry_on_recoverable_exceptions" do
    test "retries on a recoverable exception exit" do
      job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      job.enable
      MemexProjectItems::Reconciler.any_instance.stubs(:reconcile).raises(GitHub::DatabaseQueryDisabler::DatabaseDisabledError.new("Database disabled"))

      events = subscribed("enqueue_retry.active_job") do
        RepairMemexProjectItemsIndexJob.perform_now(@index.name, { cluster: @cluster })
      end

      assert_equal 1, events.size
      event = events.pop
      _, _, _, _, payload = event

      assert_kind_of GitHub::DatabaseQueryDisabler::DatabaseDisabledError, payload[:error]
    end
  end

  context "#repair!" do
    MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY.each do |klass|
      test "successfully repairs the index for the #{klass} field type" do
        field_class = klass.constantize
        next if field_class.exclude_from_index?

        field_type = field_class.data_type.to_s
        field_value_name = field_class.value_name.to_s

        helper_module = load_field_helper_module(klass)
        test_case = helper_module.setup_index_repair_test
        item, expected_slug, expected_id, expected_value = test_case.item, test_case.field.name_slug, test_case.field.id, test_case.expected_value

        enable_feature_flag(:memex_table_without_limits, item.memex_project)

        refute_predicate(expected_value, :blank?,
          "#{helper_module} returned nil or an empty collection for expected_value. " +
          "Please check that the setup_index_repair_test method sets up the required fixture data and returns the expected value to be found in the index."
        )

        repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
        repair_job.repair!

        wait_until_searchable(index_name: @index.name, id: item.id, routing: item.memex_project_id)
        item_document = @index.docs.get(type: @document_type, id: item.id, routing: item.memex_project_id)

        actual_document = item_document.dig("_source", "field_values").find { |f| f["field_slug"] == expected_slug }
        actual_value = actual_document[field_value_name]
        actual_id = actual_document["field_id"]

        value = if expected_value.is_a?(Array) && expected_value.first.respond_to?(:to_hash)
          expected_value.map { |v| v.to_hash }
        elsif expected_value.respond_to?(:to_hash)
          expected_value.to_hash
        else
          expected_value
        end

        assert_equal deep_stringify(value), actual_value
        assert_equal expected_id, actual_id
      end
    end

    test "repairs all projects regardless of memex_table_without_limits feature flag" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      total_document_count = lambda do
        @index.count_all({
          query: {
            match_all: {},
          },
        })
      end

      memex_project_without_limits_document_count = lambda do
        @index.count_all({
          query: {
            term: {
              memex_project_id: @memex_project_without_limits.id,
            }
          }
        })
      end

      memex_project_with_limits_document_count = lambda do
        @index.count_all({
          query: {
            term: {
              memex_project_id: @memex_project_with_limits.id,
            }
          }
        })
      end

      assert_changes(total_document_count, from: 0, to: @expected_item_count) do
        assert_changes(memex_project_without_limits_document_count, from: 0, to: @memex_project_without_limits_items.length) do
          assert_changes(memex_project_with_limits_document_count, from: 0, to: @memex_project_with_limits_items.length) do
            repair_job.repair!

            memex_project_item = @memex_project_without_limits_items.first
            wait_until_searchable(index_name: @index.name, id: memex_project_item.id, routing: memex_project_item.memex_project_id)

            memex_project_item = @memex_project_with_limits_items.first
            wait_until_searchable(index_name: @index.name, id: memex_project_item.id, routing: memex_project_item.memex_project_id)
          end
        end
      end
    end

    test "clears all indexed documents for project if project no longer has any items" do
      populate_elasticsearch_index!(@memex_project_without_limits_items)
      @memex_project_without_limits_items.each(&:destroy!)

      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      memex_project_without_limits_document_count = lambda do
        @index.count_all({
          query: {
            term: {
              memex_project_id: @memex_project_without_limits.id,
            }
          }
        })
      end

      assert_changes(memex_project_without_limits_document_count, from: @memex_project_without_limits_items.length, to: 0) do
        repair_job.repair!

        Elastomer::TestHelpers.index_refresh(@index.name)
      end
    end

    test "repairs projects when memex_without_limits_kill_switch feature flag enabled" do
      enable_feature_flag(:memex_without_limits_kill_switch)

      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      total_document_count = lambda do
        @index.count_all({
          query: {
            match_all: {},
          },
        })
      end

      assert_changes(total_document_count, from: 0, to: @expected_item_count) do
        repair_job.repair!

        memex_project_item = @memex_project_without_limits_items.first
        wait_until_searchable(index_name: @index.name, id: memex_project_item.id, routing: memex_project_item.memex_project_id)

        memex_project_item = @memex_project_with_limits_items.first
        wait_until_searchable(index_name: @index.name, id: memex_project_item.id, routing: memex_project_item.memex_project_id)
      end
    end
  end

  context "stats" do
    test "reports added stats" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      assert_changes -> { repair_job.stats[:added] }, from: 0, to: @expected_item_count do
        assert_changes -> { repair_job.stats[:total] }, from: 0, to: @expected_item_count do
          repair_job.repair!
        end
      end
    end

    test "reports updated stats" do
      populate_elasticsearch_index!(@memex_project_without_limits_items)
      Issue.where(id: @memex_project_without_limits_items.map(&:content_id)).update_all("title = CONCAT(title, ' updated')")

      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      assert_changes -> { repair_job.stats[:updated] }, from: 0, to: @memex_project_without_limits_items.length do
        assert_changes -> { repair_job.stats[:total] }, from: 0, to: @expected_item_count do
          repair_job.repair!
        end
      end
    end

    test "reports removed stats" do
      populate_elasticsearch_index!(@memex_project_without_limits_items)
      @memex_project_without_limits_items.each(&:destroy!)

      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      assert_changes -> { repair_job.stats[:removed] }, from: 0, to: @memex_project_without_limits_items.length do
        assert_changes -> { repair_job.stats[:total] }, from: 0, to: @memex_project_with_limits_items.length do
          repair_job.repair!
        end
      end
    end

    test "reports read stats" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)

      assert_changes -> { repair_job.stats[:total] }, from: 0, to: @expected_item_count do
        repair_job.repair!
      end
    end
  end

  context "#reset!" do
    test "resets reconcilers" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      repair_job.reconcilers.first.expects(:reset!).once

      repair_job.reset!
    end

    test "reset clears custom visited after key" do
      freeze_time

      visited_after = 1.day.ago.to_date
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      repair_job.visited_after = visited_after

      assert_changes -> { repair_job.visited_after }, from: visited_after, to: nil do
        repair_job.reset!
      end
    end
  end

  context "#reconcilers" do
    test "sets the reconciler with the job_id and attempt count" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      reconciler = repair_job.reconciler

      assert_equal reconciler.reconcile_id, repair_job.job_id
      assert_equal reconciler.attempt, repair_job.executions
    end

    test "returns MemexProjectItems::Reconciler by default" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
      reconciler, = repair_job.reconcilers

      assert_kind_of MemexProjectItems::Reconciler, reconciler
    end

    test "returns MemexProject::VisitedAfterReconciler if visited_after date is set" do
      repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster })
      repair_job.visited_after = 1.day.ago.to_date
      reconciler, = repair_job.reconcilers

      assert_kind_of MemexProject::VisitedAfterReconciler, reconciler
    end
  end

  private

  def subscribed(name, &block)
    [].tap do |events|
      ActiveSupport::Notifications.subscribed(->(*args) { events << args }, name, &block)
    end
  end
end
