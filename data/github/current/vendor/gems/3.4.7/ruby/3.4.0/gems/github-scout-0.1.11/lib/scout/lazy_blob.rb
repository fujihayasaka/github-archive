require 'scout'

module Scout
  class LazyBlob < Linguist::LazyBlob
    attr_reader :allowed_stacks

    def initialize(repo, oid, path, mode, allowed_stacks)
      super(repo, oid, path, mode)
      @allowed_stacks = allowed_stacks
    end

    def stack
      @stack ||= Scout.detect(self)
    end

    def include_in_stack_stats?
      !vendored? && !documentation? && !generated? && stack && stack.size > 0
    end
  end
end
