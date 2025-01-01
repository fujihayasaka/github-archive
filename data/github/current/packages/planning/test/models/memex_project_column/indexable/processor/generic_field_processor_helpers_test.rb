# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Interface::Indexable::Processor::GenericFieldProcessorHelpersTest < GitHub::TestCase
  include HydroTestHelpers

  class TestProcessor < MemexProjectColumn::Interface::Indexable::Processor::Base
    include MemexProjectColumn::Interface::Indexable::Processor::GenericFieldProcessorHelpers
    def self.topics; [] end
    def matching_elasticsearch_documents?; true end
    def canonical_data_present?; true end
    def dependent_mysql_replication_cluster; :fake_cluster end
    def update(es_client); Elastomer::Interfaces::Api::UpdateByQuery::Response.from_es_response({}) end
    def project_ids_to_resync_on_failure; [] end
    def updated_models; [] end
  end

  setup do
    message = build_message(
      {
        project: { id: 1 },
        project_column: { id: 2 },
        project_item: { id: 3 }
      },
      schema: "github.memex.v0.MemexProjectColumnValueDestroy"
    )
    @processor = TestProcessor.new(message)
  end

  test "raises exception when canonical column and column value data is missing" do
    @processor.expects(:memex_project_column_value).returns(nil)
    assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
      @processor.send(:field)
    end
  end
end
