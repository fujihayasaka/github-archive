# typed: true
# frozen_string_literal: true

# When we receive a protobuf primary key from the client, we will want to
# convert it to a plain old Ruby object.
module TasklistBlocks
  class PrimaryKey
    extend T::Sig

    sig { returns(String) }
    attr_reader :uuid

    sig do
      params(key: ::IssuesGraph::Proto::PrimaryKey)
        .returns(TasklistBlocks::PrimaryKey)
    end
    def self.from_proto(key:)
      new(uuid: key.uuid)
    end

    sig { params(uuid: String).void }
    def initialize(uuid:)
      @uuid = uuid
    end
  end
end
