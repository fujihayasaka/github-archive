# typed: strict
# frozen_string_literal: true

# Represents the result of a `reconcile!` or `clear!` operation.
class Search::MemexProjectItemReconciler::Result
  # The number of items that were added to Elasticsearch during the operation.
  sig { returns(Integer) }
  attr_reader :added

  # The number of items that were updated in Elasticsearch during the operation.
  sig { returns(Integer) }
  attr_reader :updated

  # The number of items that were removed from Elasticsearch during the operation.
  sig { returns(Integer) }
  attr_reader :removed

  # The number of items that were unable to be processed because a document could not be built from the DB.
  sig { returns(Integer) }
  attr_reader :incomplete

  # The number of Elasticsearch errors encountered during the operation.
  sig { returns(Integer) }
  attr_reader :errored

  sig do
    params(
      documents_to_add: T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root],
      documents_to_update: T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root],
      document_ids_to_remove: T::Set[String],
      incomplete_document_ids: T::Set[String],
      inconsistent_document_ids_to_ignore: T::Set[String],
      response: T::Hash[T.untyped, T.untyped],
      force_removed: T.nilable(Integer),
    )
    .void
  end
  def initialize(documents_to_add: [], documents_to_update: [], document_ids_to_remove: Set.new, incomplete_document_ids: Set.new, inconsistent_document_ids_to_ignore: Set.new, response: {}, force_removed: nil)
    failed_document_ids = if response["errors"]
      Set.new(
        response["items"]
          .select { |operation| operation.values.first["error"].present? }
          .map { |operation| operation.values.first["_id"] }
      )
    else
      Set.new
    end

    @added = T.let((Set.new(documents_to_add.map(&:_id)) - failed_document_ids).size, Integer)
    @updated = T.let((Set.new(documents_to_update.map(&:_id)) - inconsistent_document_ids_to_ignore - failed_document_ids).size, Integer)
    @removed = T.let(force_removed || (document_ids_to_remove - failed_document_ids).size, Integer)
    @incomplete = T.let(incomplete_document_ids.size, Integer)
    @errored = T.let(failed_document_ids.to_a.length, Integer)
  end

  # The total number of items that were added, updated, or removed during the operation.
  sig { returns(Integer) }
  def total
    added + updated + removed
  end
end
