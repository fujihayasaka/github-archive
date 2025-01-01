# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Tracks < MemexProjectColumn::Field::Base
  MAX_SEED_TOTAL = 30

  sig { override.returns(T::Boolean) }
  def self.disabled?
    true
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

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TracksValue)
  end
  def seed_elasticsearch_document(context)
    total = rand(1..MAX_SEED_TOTAL)
    completed = rand(0..total)
    percent = ((completed.to_f / total.to_f) * 100).to_i
    completion = { completed:, total:, percent: }

    Elastomer::Interfaces::Document::Tracks.new(**completion)
  end
end
