# typed: true
# frozen_string_literal: true

module DependencyGraph
  module Backfill
    autoload :Elasticsearch, "dependency_graph/backfill/elasticsearch"
    autoload :FromFile, "dependency_graph/backfill/from_file"
    autoload :PrivateRepositories, "dependency_graph/backfill/private_repositories"
  end
end
