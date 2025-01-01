# typed: false
# frozen_string_literal: true

require "test_helper"

class JobBuffer
  def self.add(value)
    values << value
  end

  def self.values
    @values ||= []
  end
end

class TestBatchedJob < BatchedJob
  PERFORMED_MESSAGE = "Performed job"
  SUCCESS_MESSAGE = "Successfully completed job"
  BATCH_MESSAGE = "Finalizing batch"

  def next_batch(cards, **options)
    cards
  end

  def process_batch(batch, *args, **options)
    with_write do
      batch.each(&:archive)
    end
  end

  def finalize_batch(batch, *args, **options)
    GitHub.logger.info(BATCH_MESSAGE)
  end

  def ensure_perform(finished_successfully:, **options)
    JobBuffer.add(PERFORMED_MESSAGE)
    JobBuffer.add(SUCCESS_MESSAGE) if finished_successfully
  end
end

class TestCustomArgsBatchedJob < BatchedJob
  def next_batch(*args, **options)
    JobBuffer.add("next_batch #{args.first}")
    JobBuffer.add("next_batch #{options[:first]}")
    []
  end

  def process_batch(batch, *args, **options)
    JobBuffer.add("process_batch #{args.drop(1).first}")
    JobBuffer.add("process_batch #{options[:second]}")
  end

  def ensure_perform(**options)
    JobBuffer.add("ensure_perform #{options[:test]}")
  end
end

class TestDoubleBatchesJob < BatchedJob
  def next_batch(batch1, batch2, **options)
    { first: batch1, second: batch2 }
  end

  def process_batch(batches, *args, **options)
    with_write do
      batches[:first].each(&:archive)
      batches[:second].each(&:archive)
    end
  end
end

class TestUnevenBatchesJob < BatchedJob
  BATCH_SIZE = 2

  # use custom offset_item_id value to query batches
  def next_batch(batch1, batch2, offset_item_id:, **options)
    batches = { first: [], second: [] }
    batches[:first] = batch1.select { |it| it.id > offset_item_id[:batch1] }.take(self.class::BATCH_SIZE) if offset_item_id[:batch1]
    batches[:second] = batch2.select { |it| it.id > offset_item_id[:batch2] }.take(self.class::BATCH_SIZE) if offset_item_id[:batch2]
    batches
  end

  def process_batch(batches, *args, **options)
    with_write do
      batches[:first].each(&:archive)
      batches[:second].each(&:archive)
    end
  end

  # override how offset_item_id is populated
  def next_batch_offset_item_id(batches, *args, **options)
    { batch1: batches[:first].map(&:id).max,
      batch2: batches[:second].map(&:id).max }
  end

  def has_next_batch?(batches, **options)
    options[:offset_item_id][:batch1] != nil || options[:offset_item_id][:batch2] != nil
  end

  def ensure_perform(**options)
    if options[:offset_item_id]
      JobBuffer.add("batch1 #{options[:offset_item_id][:batch1]}")
      JobBuffer.add("batch2 #{options[:offset_item_id][:batch2]}")
    end
  end
end

class BatchedJobTest < GitHub::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include GitHub::LoggerHelper

  setup do
    JobBuffer.values.clear
    @owner = create(:user)
    org = create(:organization, admin: @owner)
    @project = create(:project, owner: org)
    @column = create(:project_column, project: @project)
    create(:project_card, column: @column)
  end

  class TestNoNextBatchJob < BatchedJob
  end

  class TestNoProcessBatchJob < BatchedJob
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, **options)
      []
    end
  end

  class TestCustomBatchSizeJob < TestBatchedJob
    BATCH_SIZE = 2

    ## no need to override has_next_batch as it uses BATCH_SIZE internally

    def next_batch(cards, timestamp:, offset_item_id: 0, **options)
      cards.select { |card| card.id > offset_item_id }.take(self.class::BATCH_SIZE)
    end
  end

  context "extending the class" do
    test "Raises NotImplementedError if next_batch is not implemented" do
      assert_raises NotImplementedError do
        TestNoNextBatchJob.perform_now
      end
    end

    test "Raises NotImplementedError if process_batch is not implemented" do
      assert_raises NotImplementedError do
        TestNoProcessBatchJob.perform_now
      end
    end
  end

  context "simple batch tests" do
    test "Batched job is performed" do
      cards = create_list(:project_card, 3, column: @column)

      assert_logged(Body: TestBatchedJob::BATCH_MESSAGE) do
        TestBatchedJob.perform_now(cards)
      end

      assert_includes JobBuffer.values, TestBatchedJob::PERFORMED_MESSAGE
      assert_includes JobBuffer.values, TestBatchedJob::SUCCESS_MESSAGE
      assert cards.all?(&:archived?)
    end

    test "Can pass arbitrary args and options when scheduling a job" do
      TestCustomArgsBatchedJob.perform_now(123, 234, first: "first", second: "second", test: "XXX")

      assert_equal [
        "next_batch 123",
        "next_batch first",
        "process_batch 234",
        "process_batch second",
        "ensure_perform XXX",
      ], JobBuffer.values
    end

    test "collects the expected base stats when job is performed" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      cards = create_list(:project_card, 3, column: @column)
      TestBatchedJob.perform_now(cards)

      tags = GitHub.dogstats.timings("batched_job.time").first.tags
      assert_includes tags, "class:test_batched_job"
      assert_includes tags, "queue:default"
      assert_includes tags, "adapter:aqueduct"

      tags = GitHub.dogstats.timings("batched_job.total_time").first.tags
      assert_includes tags, "class:test_batched_job"
      assert_includes tags, "queue:default"
      assert_includes tags, "adapter:aqueduct"

      tags = GitHub.dogstats.counts("batched_job.batch_size").first.tags
      assert_includes tags, "class:test_batched_job"
      assert_includes tags, "queue:default"
      assert_includes tags, "adapter:aqueduct"
    end

    test "correctly signals errors in the ensure_perform hook" do
      cards = create_list(:project_card, 3, column: @column)
      error_message = "has_next_batch? raised an error"
      TestBatchedJob.any_instance.stubs(:has_next_batch?).raises(RuntimeError.new(error_message))

      assert_raises(RuntimeError) do
        TestBatchedJob.perform_now(cards)
      end

      assert_includes JobBuffer.values, TestBatchedJob::PERFORMED_MESSAGE
      refute_includes JobBuffer.values, TestBatchedJob::SUCCESS_MESSAGE
      assert_equal error_message, Failbot.exception_message_from_hash(Failbot.reports.last)
    end
  end

  context "different batch size" do
    test "Schedules job twice according to BATCH_SIZE" do
      cards = create_list(:project_card, 3, column: @column)

      assert_performed_jobs 1, only: TestCustomBatchSizeJob do
        TestCustomBatchSizeJob.perform_now(cards)
      end

      cards.each(&:reload)
      assert cards.all?(&:archived?)

      assert_equal 2, JobBuffer.values.count { |v| v == TestBatchedJob::PERFORMED_MESSAGE }
    end

    test "Report correct batch size according to BATCH_SIZE" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      cards = create_list(:project_card, 3, column: @column)

      assert_performed_jobs 1, only: TestCustomBatchSizeJob do
        TestCustomBatchSizeJob.perform_now(cards)
      end

      assert_equal 2, GitHub.dogstats.counts("batched_job.batch_size").first.value
    end

    test "Job can start from arbitrary offset_item_id" do
      cards = create_list(:project_card, 3, column: @column)

      assert_performed_jobs 1, only: TestCustomBatchSizeJob do
        # skip the first card and start the batch from the second item
        TestCustomBatchSizeJob.perform_now(cards, offset_item_id: cards.first.id)
      end

      refute cards.first.archived?
      assert cards.drop(1).all?(&:archived?)
    end
  end

  context "custom batch mechanics" do
    test "can operate on more than one batch" do
      cards1 = create_list(:project_card, 3, column: @column)
      cards2 = create_list(:project_card, 4, column: @column)
      TestDoubleBatchesJob.perform_now(cards1, cards2)

      assert cards1.all?(&:archived?)
      assert cards2.all?(&:archived?)
    end

    test "can operate on batches of different size" do

      cards1 = create_list(:project_card, 2, column: @column)
      cards2 = create_list(:project_card, 10, column: @column)

      assert_performed_jobs 6, only: TestUnevenBatchesJob do
        # speficy initial offset_item_id for every batch
        TestUnevenBatchesJob.perform_now(cards1, cards2, offset_item_id: { batch1: 0, batch2: 0 })
      end

      cards1.each(&:reload)
      cards2.each(&:reload)
      assert cards1.all?(&:archived?)
      assert cards2.all?(&:archived?)
    end
  end
end
