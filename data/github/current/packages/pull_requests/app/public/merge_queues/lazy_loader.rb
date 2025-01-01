# typed: strict
# frozen_string_literal: true

module MergeQueues
  class LazyLoader
    sig { params(repository_id: Integer, branch: String).void }
    def initialize(repository_id, branch)
      @repository_id = repository_id
      @branch = branch
      @merge_queue = T.let(nil, T.nilable(MergeQueue))
    end

    sig do
      type_parameters(:Result)
        .params(block: T.proc.params(arg0: MergeQueue).returns(T.type_parameter(:Result)))
        .returns(T.type_parameter(:Result))
    end
    def resolve(&block)
      if @merge_queue.nil?
        @merge_queue = MergeQueue.find_by!(repository_id: @repository_id, branch: @branch)
      end

      yield @merge_queue
    end
  end
end
