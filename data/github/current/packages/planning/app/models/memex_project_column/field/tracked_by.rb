# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::TrackedBy < MemexProjectColumn::Field::Base

  sig { override.returns(T::Boolean) }
  def self.disabled?
    true
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

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TrackedByValue)
  end
  def seed_elasticsearch_document(context)
    context.num_multi_select_values.times.map { |_| rand(1...1000) }.sort.map do |number|
      "#{Faker::Internet.username}/#{Faker::Lorem.word}##{number}"
    end
  end
end
