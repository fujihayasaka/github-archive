# typed: true
# frozen_string_literal: true

class CollectionChangeset
  attr_reader :collection

  def initialize(collection, collection_item_slugs = [])
    @collection = collection
    @collection_item_slugs = collection_item_slugs
  end

  def new?
    @collection.new_record?
  end

  def new_items
    @changes["items"] && @changes["items"]["new"]
  end

  def changed?
    !new? && @changes.present?
  end

  def deleted?
    @collection.destroyed?
  end

  def each
    sorted_changes.each_pair do |field, value|
      yield field, value
    end
  end

  def to_h
    sorted_changes.dup
  end

  def determine_changes!
    @changes = @collection.changed_attributes.inject({}) do |hash, (key, old_value)|
      old_value = old_value.force_encoding("UTF-8") if old_value.is_a?(String)

      new_value = collection.send(key)
      new_value.force_encoding("UTF-8") if new_value.is_a?(String)

      unless old_value == new_value
        hash[key] = old_value
      end
      hash
    end

    old_item_slugs = collection.items.map(&:slug)

    unless old_item_slugs.sort == @collection_item_slugs.sort
      @changes["items"] = {
        "old" => old_item_slugs.join(", "),
        "new" => @collection_item_slugs.join(", "),
      }
    end
  end

  private

  def sorted_changes
    @sorted_changes ||= @changes.sort_by { |field, _value| field }.to_h
  end
end
