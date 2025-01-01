# typed: true
# frozen_string_literal: true

require "test_helper"

module MemexProjectItems
  class ReconcilerTest < GitHub::TestCase
    include GitHub::LoggerHelper
    include MemexHelpers

    fixtures do
      @reconciled_user = create(:user)
    end

    def create_reconciler(opts = {})
      MemexProjectItems::Reconciler.new({
        index: opts.fetch(:index, Elastomer::Indexes::MemexProjectItems.new),
        group_key: "reconciler-test",
        reconcile_id: SecureRandom.hex,
        attempt: 1,
      }.merge(opts))
    end

    setup do
      Failbot.reports.clear
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @index = Elastomer::Indexes::MemexProjectItems.new
      @document_type = Elastomer::Adapters::MemexProjectItem.document_type
      @cluster = Elastomer.router.cluster_for_index(@index.name)
      @reconciler = create_reconciler(index: @index).tap(&:reset!)
      @organization = create(:organization)
      @user = create(:verified_user).tap { |user| @organization.add_member(user) }
      @memex_project_without_limits = create(:memex_project, owner: @organization, creator: @user)
      @memex_project_with_limits = create(:memex_project, owner: @organization, creator: @user)
      create_list(:memex_project_item, 2, memex_project: @memex_project_without_limits)

      setup_search

      enable_feature_flag(:memex_table_without_limits, @memex_project_without_limits)
      disable_feature_flag(:memex_increased_issues_graph_timeouts)
    end

    test "default to raising errors to allow for bubbling up exceptions necessary for retries" do
      assert_equal true, @reconciler.raise_errors
    end

    test "projects are iterated on in reasonable batch size" do
      assert_equal MemexProjectItems::Reconciler::MEMEX_PROJECT_BATCH_SIZE, @reconciler.limit
    end

    test "last_id returns last project id for progress reporting" do
      assert_equal @memex_project_with_limits.id, @reconciler.last_id
    end

    test "progress determines percentage based on last reconciled project" do
      MemexProjectItems::Reconciler.stub_const(:MEMEX_PROJECT_BATCH_SIZE, 1) do
        first_batch_reconciler = create_reconciler(index: @index).tap(&:reset!)
        assert_equal 0.0, first_batch_reconciler.progress
        first_batch_reconciler.reconcile

        next_batch_reconciler = create_reconciler(index: @index)
        assert next_batch_reconciler.progress > 0.0, "Expected progress to be greater than 0.0"
        assert next_batch_reconciler.progress < 100.0, "Expected progress to be less than 100.0"
        next_batch_reconciler.reconcile

        final_batch_reconciler = create_reconciler(index: @index)
        assert_equal 100.0, final_batch_reconciler.progress
      end
    end

    context "#memex_projects_reconciled_count" do
      test "returns count of reconciled projects" do
        assert_changes -> { @reconciler.memex_projects_reconciled_count }, from: 0, to: 2 do
          @reconciler.reconcile
        end
      end

      test "increments number of projects successfully reconciled during the attempt" do
        MemexPerformanceStatsHelper.stubs(:bucketed_value)
          .returns(1).then # First project, first attempt
          .raises(StandardError) # Second project, first attempt

        assert_changes -> { @reconciler.memex_projects_reconciled_count }, from: 0, to: 1 do
          assert_raises StandardError do
            @reconciler.reconcile
          end
        end
      end
    end

    context "#reconciler_batches" do
      test "returns known reconciler batches" do
        MemexProjectItems::Reconciler.stub_const(:MEMEX_PROJECT_BATCH_SIZE, 1) do
          first_batch_reconciler = create_reconciler(index: @index, reconcile_id: "first").tap(&:reset!)
          second_batch_reconciler = create_reconciler(index: @index, reconcile_id: "second")

          expected_batches = [
            first_batch_reconciler.reconciler_batch_key,
            second_batch_reconciler.reconciler_batch_key,
          ].sort

          assert_changes -> { first_batch_reconciler.reconciler_batches.sort }, from: [], to: expected_batches do
            first_batch_reconciler.reconciler_memex_project_ids
            second_batch_reconciler.reconciler_memex_project_ids
          end
        end
      end
    end

    context "#reconciler_batches_count" do
      test "returns count of known reconciler batches" do
        MemexProjectItems::Reconciler.stub_const(:MEMEX_PROJECT_BATCH_SIZE, 1) do
          first_batch_reconciler = create_reconciler(index: @index, reconcile_id: "first").tap(&:reset!)
          second_batch_reconciler = create_reconciler(index: @index, reconcile_id: "second")

          assert_changes -> { first_batch_reconciler.reconciler_batches_count }, from: 0, to: 2 do
            first_batch_reconciler.reconciler_memex_project_ids
            second_batch_reconciler.reconciler_memex_project_ids
          end
        end
      end
    end

    context "#finished?" do
      test "returns true when marked as finished" do
        assert_changes -> { @reconciler.finished? }, from: false, to: true do
          @reconciler.finish!
        end
      end

      test "returns false during retry attempt when reconciler is finished" do
        refute_predicate @reconciler, :retry_attempt?, "Expected reconciler to not be a retry attempt"
        assert_changes -> { @reconciler.finished? }, from: false, to: true do
          @reconciler.finish!
        end

        reconciler = create_reconciler(index: @index, reconcile_id: @reconciler.reconcile_id, attempt: 2)
        assert_predicate reconciler, :retry_attempt?, "Expected reconciler to be a retry attempt"
        refute_predicate reconciler, :finished?, "Expected reconciler to not be finished"
      end
    end

    context "#reconciler_memex_project_ids" do
      test "returns first page of projects since last reconciled project" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        MemexProjectItems::Reconciler.stub_const(:MEMEX_PROJECT_BATCH_SIZE, 1) do
          assert_equal [@memex_project_without_limits.id], reconciler.reconciler_memex_project_ids
          reconciler.reconcile

          next_batch_reconciler = create_reconciler(index: @index)
          assert_equal [@memex_project_with_limits.id], next_batch_reconciler.reconciler_memex_project_ids
        end
      end

      test "sets offset after computing initial reconcile batch" do
        expected_batch = [@memex_project_without_limits.id, @memex_project_with_limits.id]
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)

        assert_changes -> { reconciler.get_offset }, from: 0, to: @memex_project_with_limits.id do
          reconciler.reconciler_memex_project_ids
        end
      end

      test "stores reconcile batch after computing initial reconcile batch" do
        reconcile_id = "initial"
        expected_batch = [@memex_project_without_limits.id, @memex_project_with_limits.id]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        # get_reconciler_batch is memoized, can't fetch it twice on same instance
        same_batch_reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1)

        assert_equal [], reconciler.get_reconciler_batch
        reconciler.reconciler_memex_project_ids

        assert_equal expected_batch, same_batch_reconciler.get_reconciler_batch
      end

      test "stores reconcile batch key after computing initial reconcile batch" do
        reconcile_id = "initial"
        expected_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)

        assert_changes -> { reconciler.reconciler_batches }, from: [], to: expected_reconciler_batches do
          reconciler.reconciler_memex_project_ids
        end
      end

      test "returns existing reconcile batch if retry_attempt" do
        reconcile_id = "retry"
        expected_batch = [@memex_project_without_limits.id, @memex_project_with_limits.id]
        first_reconcile_attempt = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        first_reconcile_attempt.stubs(:reconcile_memex_project).raises(StandardError)

        assert_changes -> { first_reconcile_attempt.get_offset }, from: 0, to: @memex_project_with_limits.id do
          assert_equal expected_batch, first_reconcile_attempt.reconciler_memex_project_ids
        end

        second_reconcile_attempt = create_reconciler(index: @index, reconcile_id:, attempt: 2)
        assert_equal expected_batch, second_reconcile_attempt.reconciler_memex_project_ids
      end
    end

    context "#get_reconciler_batch" do
      test "returns batch" do
        reconciler = create_reconciler(index: @index, attempt: 1)
        reconciler.reconciler_memex_project_ids

        expected_batch = [@memex_project_without_limits.id, @memex_project_with_limits.id]
        assert_equal expected_batch, reconciler.get_reconciler_batch
      end

      test "returns empty batch when accessing during initial batch before value is set" do
        reconciler = create_reconciler(index: @index, attempt: 1)

        assert_equal [], reconciler.get_reconciler_batch
      end

      test "raises exception if retry attempt does not produce reconcile batch" do
        reconciler = create_reconciler(index: @index, attempt: 2)

        assert_raises MemexProjectItems::Reconciler::MissingReconcileBatchError do
          reconciler.get_reconciler_batch
        end
      end
    end

    context "#retry_attempt?" do
      test "returns true if attempt is greater than 1" do
        reconciler = create_reconciler(index: @index, attempt: 2)
        assert_predicate reconciler, :retry_attempt?
      end

      test "returns false if attempt is not greater than 1" do
        reconciler = create_reconciler(index: @index, attempt: 1)
        refute_predicate reconciler, :retry_attempt?
      end
    end

    context "#reconcile" do
      test "only repairs projects with memex_table_without_limits feature flag enabled" do
        assert_changes -> { @reconciler.get_offset }, from: 0, to: @memex_project_with_limits.id do
          @reconciler.reconcile
        end
      end

      test "clears current batch from reconcile batches after successfully reconciling" do
        reconcile_id = "initial"
        expected_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        reconciler.reconciler_memex_project_ids # Adds the batch key

        assert_changes -> { reconciler.reconciler_batches }, from: expected_reconciler_batches, to: [] do
          reconciler.reconcile
        end
      end

      test "keeps track of successful reconciles on a retry attempt" do
        reconcile_id = "initial"
        expected_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 2).tap(&:reset!)
        reconciler.calculate_reconciler_batch # Adds the batch key

        assert_changes -> { GitHub.dogstats.counts("memex_project.reconciler.batch.reconciled").length }, from: 0, to: 1 do
          reconciler.reconcile
        end
      end

      test "does not clear current batch from reconcile batches if exception is raised" do
        reconcile_id = "initial"
        expected_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        reconciler.stubs(:reconcile_memex_project).raises(StandardError)

        assert_changes -> { reconciler.reconciler_batches }, from: [], to: expected_reconciler_batches do
          assert_raises StandardError do
            reconciler.reconcile
          end
        end
      end

      test "does not raise an exception if project prepared in batch is no longer found" do
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)

        assert_equal [@memex_project_without_limits.id, @memex_project_with_limits.id], reconciler.reconciler_memex_project_ids
        @memex_project_with_limits.destroy!

        assert_changes -> { reconciler.reconciler_batches_count }, from: 1, to: 0 do
          assert_changes -> { reconciler.memex_projects_reconciled_count }, from: 0, to: 1 do
            reconciler.reconcile
          end
        end
      end

      test "resumes reconciling remaining projects on retry" do
        reconcile_id = "initial"
        initial_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        MemexPerformanceStatsHelper.stubs(:bucketed_value)
          .returns(1).then # First project, first attempt
          .raises(StandardError).then # Second project, first attempt
          .returns(1) # Second project, second attempt

        assert_raises StandardError do
          reconciler.reconcile
        end

        retry_batch_reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 2)
        assert_equal [@memex_project_with_limits.id], retry_batch_reconciler.reconciler_memex_project_ids
        assert_changes -> { retry_batch_reconciler.reconciler_batches }, from: initial_reconciler_batches, to: [] do
          retry_batch_reconciler.reconcile
        end
      end

      test "re-raises any StandardError raised" do
        @reconciler.stubs(:reconcile_memex_project).raises(StandardError)

        assert_raises StandardError do
          @reconciler.reconcile
        end
      end

      test "includes project metadata in Failbot report" do
        Search::MemexProjectItemReconciler.any_instance.stubs(:reconcile!).raises(StandardError)

        assert_raises StandardError do
          @reconciler.reconcile
        end

        assert report = Failbot.reports.last
        assert_equal @memex_project_without_limits.id, report["gh.memex.project.id"]
      end

      test "increments lock error but does not raise when mutex lock cannot be obtained" do
        @reconciler.stubs(:reconcile_memex_project).raises(GitHub::Redis::Mutex::LockError)

        assert_changes -> { GitHub.dogstats.increments("search.repair.lock_error").length }, from: 0, to: 1 do
          @reconciler.reconcile
        end
      end

      test "increments batch retry metric on retry attempts" do
        reconciler = create_reconciler(index: @index, attempt: 2).tap(&:reset!)
        reconciler.calculate_reconciler_batch

        assert_changes -> { GitHub.dogstats.increments("memex_project.reconciler.batch.retry").length }, from: 0, to: 1 do
          reconciler.reconcile
        end
      end

      test "does not increment batch retry metric on initial attempts" do
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)

        assert_no_changes -> { GitHub.dogstats.increments("memex_project.reconciler.batch.retry").length } do
          reconciler.reconcile
        end
      end

      test "stores consistency score when writing to primary index" do
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.stubs(:primary_index?).returns(true)

        assert_predicate reconciler, :primary_index?
        refute_empty @memex_project_without_limits.memex_project_items

        assert_difference -> { MemexProjectElasticsearchConsistency.where(memex_project_id: @memex_project_without_limits.id).count } do
          reconciler.reconcile
        end

        consistency_record = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @memex_project_without_limits.id)
        assert T.must(consistency_record.repair_started_at) < consistency_record.evaluated_at
        refute_nil consistency_record.evaluated_at
        refute_nil consistency_record.repair_finished_at
        assert_equal 1.0, consistency_record.consistency
      end

      test "does not store consistency score when writing to non-primary index" do
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.stubs(:primary_index?).returns(false)

        refute_predicate reconciler, :primary_index?
        refute_empty @memex_project_without_limits.memex_project_items

        assert_no_difference -> { MemexProjectElasticsearchConsistency.where(memex_project_id: @memex_project_without_limits.id).count } do
          reconciler.reconcile
        end
      end

      test "project that reconciles without errors is considered consistent" do
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.stubs(:primary_index?).returns(true)

        refute_empty @memex_project_without_limits.memex_project_items
        # Populate the index with all but 1 item
        populate_elasticsearch_index!(@memex_project_without_limits.memex_project_items[1..])
        reconciler.reconcile

        actual_consistency_score = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @memex_project_without_limits.id).consistency
        assert_equal 1.0, actual_consistency_score, "Expected project to become fully consistent"
      end

      test "project with no items is considered consistent" do
        @memex_project_without_limits.memex_project_items.destroy_all
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.stubs(:primary_index?).returns(true)

        assert_empty @memex_project_without_limits.memex_project_items

        assert_nil MemexProjectElasticsearchConsistency.find_by(memex_project_id: @memex_project_without_limits.id), "Expected no consistency record to exist"

        reconciler.reconcile

        actual_consistency_score = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @memex_project_without_limits.id).consistency
        assert_equal 1.0, actual_consistency_score, "Expected project to become fully consistent"
      end

      test "project that reconciles with errors is not considered consistent" do
        refute_empty @memex_project_without_limits.memex_project_items
        inconsistent_item = @memex_project_without_limits.memex_project_items[0]
        consistent_items = @memex_project_without_limits.memex_project_items[1..]
        # Populate the index with all but 1 item so that this 1 item will be reported as inconsistent
        populate_elasticsearch_index!(consistent_items)

        items = [].tap do |items|
          items << { "index" => { "_id" => inconsistent_item.id.to_s, "status" => 400, "error" => "first error" } }

          consistent_items.each do |item|
            items << { "update" => { "_id" => item.id.to_s, "result" => "updated" } }
          end
        end

        Elastomer::Index.any_instance.stubs(:bulk).returns({
          "errors" => true,
          "items" => items,
        })

        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.stubs(:primary_index?).returns(true)

        reconciler.reconcile

        actual_consistency_score = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @memex_project_without_limits.id).consistency
        assert_equal 0.5, actual_consistency_score, "Expected project to not be consistent"
      end

      test "on exception, updates repair_started_at but leaves all other attributes untouched" do
        seed_time = Time.current.beginning_of_day
        attrs = { consistency: 0.5, repair_started_at: seed_time, repair_finished_at: seed_time, evaluated_at: seed_time }
        MemexProjectElasticsearchConsistency
          .find_or_initialize_by(memex_project_id: @memex_project_without_limits.id)
          .update!(**attrs)
        Search::MemexProjectItemReconciler.any_instance.stubs(:reconcile!).raises(StandardError)

        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.stubs(:primary_index?).returns(true)

        assert_raises StandardError do
          reconciler.reconcile
        end

        consistency_record = MemexProjectElasticsearchConsistency.find_by!(memex_project_id: @memex_project_without_limits.id)
        assert_equal attrs[:consistency], consistency_record.consistency
        assert_same_time attrs[:evaluated_at], consistency_record.evaluated_at
        assert_same_time attrs[:repair_finished_at], consistency_record.repair_finished_at
        assert attrs[:repair_started_at] < consistency_record.repair_started_at
      end
    end

    context "#failed_reconciler_batches" do
      test "returns known failed reconciler batches" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        expected_batches = [
          reconciler.reconciler_batch_key,
        ]

        assert_changes -> { reconciler.failed_reconciler_batches }, from: [], to: expected_batches do
          reconciler.failed!(StandardError.new)
        end
      end

      test "does not include successful batches" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_no_changes -> { reconciler.failed_reconciler_batches }, from: [] do
          reconciler.reconcile
        end
      end
    end

    context "#failed_reconciler_batches_count" do
      test "increments when batch fails" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_changes -> { reconciler.failed_reconciler_batches_count }, from: 0, to: 1 do
          reconciler.failed!(StandardError.new)
        end
      end

      test "does not increment when batch succeeds" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_no_changes -> { reconciler.failed_reconciler_batches_count }, from: 0 do
          reconciler.reconcile
        end
      end
    end

    context "#failed!" do
      test "marks batch as failed" do
        reconcile_id = "initial"
        expected_failed_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)

        assert_changes -> { reconciler.failed_reconciler_batches }, from: [], to: expected_failed_reconciler_batches do
          reconciler.failed!(StandardError.new)
        end
      end

      test "increments error count by number of projects remaining in batch" do
        repair_job = RepairMemexProjectItemsIndexJob.new(@index.name, { cluster: @cluster }).tap(&:reset!)
        reconciler = repair_job.reconciler

        assert_changes -> { repair_job.stats[:error] }, from: 0, to: 2 do
          reconciler.failed!(StandardError.new)
        end
      end

      test "clears reference to in progress batch" do
        reconcile_id = "initial"
        expected_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        reconciler.reconciler_memex_project_ids

        assert_changes -> { reconciler.reconciler_batches }, from: expected_reconciler_batches, to: [] do
          reconciler.failed!(StandardError.new)
        end
      end

      test "does not clear reference to ids stored in batch" do
        expected_batch = [@memex_project_without_limits.id, @memex_project_with_limits.id]
        reconciler = create_reconciler(index: @index, attempt: 1).tap(&:reset!)
        reconciler.reconciler_memex_project_ids

        assert_no_changes -> { reconciler.get_reconciler_batch }, from: expected_batch do
          reconciler.failed!(StandardError.new)
        end
      end

      test "increments batch failed metric" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_changes -> { GitHub.dogstats.increments("memex_project.reconciler.batch.failed").length }, from: 0, to: 1 do
          reconciler.failed!(StandardError.new)
        end
      end

      test "reports error to Failbot" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_changes -> { Failbot.reports.size }, from: 0, to: 1 do
          reconciler.failed!(StandardError.new)
        end
      end
    end

    context "#reset!" do
      test "clears reconciler batches" do
        reconcile_id = "initial"
        expected_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        reconciler.reconciler_memex_project_ids # Adds the batch key

        assert_changes -> { reconciler.reconciler_batches }, from: expected_reconciler_batches, to: [] do
          reconciler.reset!
        end
      end

      test "clears reconciler failed batches" do
        reconcile_id = "initial"
        initial_failed_reconciler_batches = ["memex_project_item/reconciler_batch/#{reconcile_id}"]
        reconciler = create_reconciler(index: @index, reconcile_id:, attempt: 1).tap(&:reset!)
        reconciler.failed!(StandardError.new)

        assert_changes -> { reconciler.failed_reconciler_batches }, from: initial_failed_reconciler_batches, to: [] do
          reconciler.reset!
        end
      end
    end
  end
end
