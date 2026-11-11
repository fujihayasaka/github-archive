# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class KeyOnlyItem
    attr_reader :owner_id
    attr_reader :uuid
    attr_reader :item_id

    def initialize(owner_id:, uuid: nil, item_id: nil)
      @owner_id = owner_id
      @uuid = uuid
      @item_id = item_id
    end

    def ==(other)
      @owner_id == other.owner_id && @uuid == other.uuid && @item_id == other.item_id
    end

    def to_hierarchy_model
      model = {
        key: {
          ownerId: @owner_id,
        }
      }
      model[:key][:primaryKey] = IssuesGraph::Proto::PrimaryKey.new(uuid: @uuid) if @uuid
      model[:key][:itemId] = @item_id if @item_id
      model
    end
  end
end
