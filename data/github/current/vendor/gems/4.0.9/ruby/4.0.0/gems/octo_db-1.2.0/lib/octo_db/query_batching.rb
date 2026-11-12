# typed: strict
# frozen_string_literal: true

module OctoDb
  module QueryBatching
    autoload :IteratorBuilder, "octo_db/query_batching/iterator_builder"
    autoload :ScopeIterator, "octo_db/query_batching/scope_iterator"
  end
end
