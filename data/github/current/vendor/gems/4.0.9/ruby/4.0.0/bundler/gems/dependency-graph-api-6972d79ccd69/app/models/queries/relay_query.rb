module Queries
  module RelayQuery
    include Enumerable

    DEFAULT_LIMIT = 20

    def each(*args)
      raise NotImplementedError
    end

    def has_previous?
      raise NotImplementedError
    end

    def has_next?
      raise NotImplementedError
    end

    def first(n)
      @limit = n
      self
    end

    def after(id)
      @after = id
      self
    end

    def last(n)
      @limit = n
      self
    end

    def before(id)
      @before = id
      self
    end

    def limit
      @limit || DEFAULT_LIMIT
    end

    private

    def after?
      @after.present?
    end

    def before?
      @before.present?
    end
  end
end
