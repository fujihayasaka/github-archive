# typed: strict
# frozen_string_literal: true

# Internal representation of a document that we've found in Elasticsearch.
class Search::MemexProjectItemReconciler::Document
  sig { returns(String) }
  attr_reader :id

  sig { returns(String) }
  attr_reader :routing

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :source

  sig { params(document: T::Hash[String, T.untyped]).void }
  def initialize(document)
    @id = T.let(document["_id"], String)
    @routing = T.let(document["_routing"], String)
    @source = T.let(document["_source"], T::Hash[String, T.untyped])
  end
end
