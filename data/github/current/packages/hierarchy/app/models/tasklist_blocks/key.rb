# typed: true
# frozen_string_literal: true

# When we receive a protobuf key from the client, we will want to convert it to
# a plain old Ruby object.
module TasklistBlocks
  class Key
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :owner_id
    sig { returns(Integer) }
    attr_reader :item_id
    sig { returns(T.nilable(TasklistBlocks::PrimaryKey)) }
    attr_reader :primary_key

    sig do
      params(key: ::IssuesGraph::Proto::Key).returns(TasklistBlocks::Key)
    end
    def self.from_proto(key:)
      new(
        owner_id: key.ownerId,
        item_id: key.itemId,
        primary_key: key.primaryKey,
      )
    end

    sig do
      params(
        owner_id: Integer,
        item_id: Integer,
        primary_key: T.nilable(IssuesGraph::Proto::PrimaryKey),
      ).void
    end
    def initialize(owner_id:, item_id:, primary_key:)
      @owner_id = owner_id
      @item_id = item_id
      @primary_key = TasklistBlocks::PrimaryKey.from_proto(key: primary_key) if primary_key
    end
  end
end
