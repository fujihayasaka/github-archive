module Snapshots
  class Metadata
    attr_reader :push_id, :sha, :ref

    def initialize(push_id:, sha:, ref:)
      @push_id = push_id
      @sha = sha
      @ref = ref
    end
  end
end
