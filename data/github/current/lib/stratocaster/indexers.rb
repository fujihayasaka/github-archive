# typed: true
# frozen_string_literal: true

module Stratocaster
  module Indexers
    autoload :NullIndexer, "stratocaster/indexers/null_indexer"
    autoload :DelayedGlobalIndexer, "stratocaster/indexers/delayed_global_indexer"
    autoload :GlobalIndexer, "stratocaster/indexers/global_indexer"
    autoload :MemoryIndexer, "stratocaster/indexers/memory_indexer"
    autoload :MysqlIndexer, "stratocaster/indexers/mysql_indexer"
    autoload :Proxy, "stratocaster/indexers/proxy"
  end
end
