# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::TrackedBy < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  # We don't register any processors here because TrackedBy is no longer supported in projects.
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
    Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_batch_method(items, :tracked_by_items)
  rescue MemexProjectItem::ItemPrefillError
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TrackedByValue)
  end
  def elasticsearch_document(item)
    item.tracked_by_items&.sort_by(&:number)&.map do |i|
      h = i.to_h
      "#{h[:owner_login]}/#{h[:repository_name]}##{h[:display_number]}"
    end
  rescue MemexProjectItem::ItemPrefillError
    nil
  end
end
