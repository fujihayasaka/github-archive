# typed: true
# frozen_string_literal: true

require "test_helper"

class BaseTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include DogstatsTestHelpers

  class TestProcessor < MemexProjectColumn::Interface::Indexable::Processor::Base
    def self.topics
      []
    end

    def matching_elasticsearch_documents?
      true
    end

    def canonical_data_present?
      true
    end

    def dependent_mysql_replication_cluster
      :fake_cluster
    end

    def update(es_client)
      Elastomer::Interfaces::Api::UpdateByQuery::Response.from_es_response(
        "took" => 9,
        "timed_out" => false,
        "total" => 1,
        "updated" => 0,
        "deleted" => 0,
        "batches" => 1,
        "version_conflicts" => 1,
        "noops" => 1,
        "retries" => { "bulk" => 0, "search" => 0 },
        "throttled_millis" => 0,
        "requests_per_second" => -1.0,
        "throttled_until_millis" => 0,
        "failures" => []
      )
    end

    def document_type
      super
    end

    def project_ids_to_resync_on_failure
      []
    end

    def updated_models
      []
    end
  end

  setup do
    setup_search
    example_schema = "github.memex.v0.DraftIssueUpdateTitle"
    @message = build_message({}, schema: example_schema)
  end

  test "returns document type value in ES5", es_5_only: true do
    processor = TestProcessor.new(@message)

    expected_type = "memex_project_item"
    assert_equal expected_type, processor.document_type
  end

  test "does not return document type value in ES8", es_8_only: true do
    processor = TestProcessor.new(@message)
    refute processor.document_type
  end

  context "#consume" do
    test "returns a processed result of message ignored when message is invalid" do
      processor = TestProcessor.new(@message)
      processor.stubs(:valid_message?).returns(false)
      result = processor.consume

      assert_equal 1, result.size
      assert_processed_result(result.first)
      assert T.must(result.first).message_ignored?
    end

    test "returns a processed result of no matching docs when no docs match" do
      processor = TestProcessor.new(@message)
      processor.stubs(:matching_elasticsearch_documents?).returns(false)
      result = processor.consume

      assert_equal 1, result.size
      assert_processed_result(result.first)
      assert_predicate T.must(result.first), :no_matching_docs?
    end

    test "returns a processed result of no content missing when canonical data is not present" do
      processor = TestProcessor.new(@message)
      processor.stubs(:canonical_data_present?).returns(false)
      result = processor.consume

      assert_equal 1, result.size
      assert_processed_result(result.first)
      assert_predicate T.must(result.first), :content_missing?
    end

    test "returns a processed result without error info if the update succeeds" do
      result = TestProcessor.new(@message).consume

      assert_equal 1, result.size
      assert_processed_result(result.first)
      refute_predicate T.must(result.first), :failure_reason?
    end

    test "instruments timing metrics for interface methods" do
      TestProcessor.new(@message).consume

      [
        :valid_message?,
        :matching_elasticsearch_documents?,
        :canonical_data_present?,
        :update,
        :consume,
      ].each do |method|
        assert_dogstats_distribution(
          1,
          MemexProjectColumn::Interface::Indexable::Processor::Base::METRIC_NAME_INDEX_TIME,
          tags: ["action:#{method}", "processor:test_processor", "aborted:false"]
        )
      end
    end

    test "instruments distributed traces for interface methods" do
      TestProcessor.new(@message).consume

      [
        :valid_message?,
        :matching_elasticsearch_documents?,
        :canonical_data_present?,
        :update,
        :consume,
      ].each do |method|
        assert_equal "test_processor", find_span(method).attributes["processor"]
      end
    end

    test "records the cluster that we checked for replication on `canonical_data_present?` telemetry" do
      result = TestProcessor.new(@message).consume

      assert_dogstats_distribution(
        1,
        MemexProjectColumn::Interface::Indexable::Processor::Base::METRIC_NAME_INDEX_TIME,
        tags: [
          "action:canonical_data_present?",
          "processor:test_processor",
          "dependent_mysql_replication_cluster:fake_cluster"
        ]
      )

      assert_equal(
        "fake_cluster",
        find_span("canonical_data_present?").attributes["dependent_mysql_replication_cluster"]
      )
    end

    test "records whether or not we aborted at a particular stage of the pipeline" do
      processor = TestProcessor.new(@message)
      processor.stubs(:matching_elasticsearch_documents?).returns(false)
      processor.consume

      assert_dogstats_distribution(
        1,
        MemexProjectColumn::Interface::Indexable::Processor::Base::METRIC_NAME_INDEX_TIME,
        tags: ["action:matching_elasticsearch_documents?", "processor:test_processor", "aborted:true"]
      )

      assert_equal true, find_span("matching_elasticsearch_documents?").attributes["aborted"]
    end

    test "records whether or not we aborted the overall `consume` method" do
      processor = TestProcessor.new(@message)
      processor.stubs(:valid_message?).returns(false)
      processor.consume

      assert_dogstats_distribution(
        1,
        MemexProjectColumn::Interface::Indexable::Processor::Base::METRIC_NAME_INDEX_TIME,
        tags: ["action:consume", "processor:test_processor", "aborted:true"]
      )

      assert_equal true, find_span("consume").attributes["aborted"]
    end
  end

  context "#_canonical_data_present? (private)" do
    test "waits for replication when a dependent cluster is configured" do
      wait_stub = stub(wait!: nil)

      WaitForReplication
        .expects(:new)
        .with(anything, has_entries(store_name: :fake_cluster, max_wait_seconds: 8))
        .returns(wait_stub)

      wait_stub.expects(:wait!)

      TestProcessor.new(@message).send(:_canonical_data_present?)
    end

    test "does not wait for replication without a dependent cluster" do
      WaitForReplication.any_instance.expects(:wait!).never

      processor = TestProcessor.new(@message)
      processor.stubs(:dependent_mysql_replication_cluster).returns(nil)

      processor.send(:_canonical_data_present?)
    end
  end

  private def assert_processed_result(result)
    assert result.is_a?(MemexProjectColumn::Interface::Indexable::Processor::ProcessedResult)
  end

  private def find_span(method_name, class_name: "base_test/test_processor")
    full_method_name = [class_name, method_name].join("#")
    span = find_span_by(name: full_method_name)
    refute_nil span, "expected span named #{full_method_name}"
    span
  end
end
