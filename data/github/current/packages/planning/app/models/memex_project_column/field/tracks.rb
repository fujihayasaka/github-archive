# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Tracks < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  MAX_SEED_TOTAL = 30

  # We don't register any processors here because Tracks is no longer supported in projects.
  # We expect the full field implementation to removed before long.
  sig { override.returns(T::Array[String]) }
  def self.register_processors
    []
  end

  sig { override.returns(T::Boolean) }
  def self.disabled?
    true
  end

  sig { override.returns(T::Boolean) }
  def self.web_api_serializable?
    false
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      completed: Elastomer::Interfaces::Mapping::FieldDataTypes::Integer.new,
      total: Elastomer::Interfaces::Mapping::FieldDataTypes::Integer.new,
      percent: Elastomer::Interfaces::Mapping::FieldDataTypes::Integer.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_batch_method(items, :completion)
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TracksValue)
  end
  def elasticsearch_document(item)
    completion = item.completion
    return unless completion

    Elastomer::Interfaces::Document::Tracks.new(**completion)
  end
end
