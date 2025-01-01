# typed: true
# frozen_string_literal: true

require "test_helper"

class GenericFieldValueDestroyStrategyTest < GitHub::TestCase
  include HydroTestHelpers

  class TestProcessorComposingUpdate < MemexProjectColumn::Interface::Indexable::Processor::Base
    include MemexProjectColumn::Interface::Indexable::Processor::GenericFieldValueDestroyStrategy
    # update is composed from the GenericFieldValueDestroyStrategy module, but everything else is overridden to
    # facilitate testing.
    def field_class; MemexProjectColumn::Field::Date end
    def self.topics; [] end
    def matching_elasticsearch_documents?; true end
    def canonical_data_present?; true end
    def dependent_mysql_replication_cluster; :fake_cluster end
    def project_ids_to_resync_on_failure; [] end
    def updated_models; [] end
    def field; MemexProjectColumn::Field::Date.new end
  end

  setup do
    @search_client = Search::Memex::Client.new(Elastomer::Indexes::MemexProjectItems.new)
    message = build_message(
      {
        project: { id: 1 },
        project_column: { id: 2 },
        project_item: { id: 3 }
      },
      schema: "github.memex.v0.MemexProjectColumnValueDestroy"
    )
    @processor = TestProcessorComposingUpdate.new(message)
  end

  test "raises exception when project item does not exist" do
    assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
      @processor.update(@search_client)
    end
  end
end
