# typed: strict
# frozen_string_literal: true

# This interface collects all the behaviour needed to write data for a field supported in GitHub Projects to
# Elasticsearch.
#
# Rather than including this module directly, most consumers will inherit this interface via
# `MemexProjectColumn::Field::Base`, which is the base class for all fields supported by GitHub Projects. As a result,
# many comments in this file will refer to "this field", meaning the `MemexProjectColumn::Field::Base` subclass that
# includes this module.
#
# This interface only covers write behaviour; read behaviour is covered by `MemexProjectColumn::Interface::Queryable`.
module MemexProjectColumn::Interface::Indexable
  extend T::Helpers
  interface!

  # This error should be raised from `elasticsearch_document` if we encounter a race condition in which the data
  # we are attempting to write to Elasticsearch no longer exists.
  #
  # EXAMPLE:
  #
  #  def elasticsearch_document(item)
  #    # We want to return the repository name, but the repository itself is missing: notify consumers by raising
  #    raise CanonicalDataMissingError if item.repository.nil?
  #
  #    # Otherwise, we know the repository exists, so we return its name
  #    item.repository.full_name
  #  end
  class CanonicalDataMissingError < StandardError; end

  module ClassMethods
    extend T::Helpers
    abstract!

    # Returns the key from the `MemexProjectColumn.data_types` enum for this field type.
    #
    # EXAMPLE:
    #
    #  def data_type
    #    :text
    #  end
    sig { abstract.returns(Symbol) }
    def data_type; end

    # Returns an object that describes the schema (or "mapping") for this field in Elasticsearch.
    #
    # For more details on the mapping process, see:
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html
    #
    # You may need to implement a new `Mapping::FieldDataType` to use as your return value if there isn't already one
    # that corresponds to the Elasticsearch type you want to use.
    #
    # If this field contains text, you may be tempted to return `Mapping::FieldDataTypes::Text` here. However if users
    # should be able to sort and group the contents of this field, you should use
    # `Mapping::FieldDataTypes::KeywordMultiField` instead.
    #
    # EXAMPLE:
    #
    #   def elasticsearch_mapping
    #     Elastomer::Interfaces::Mapping::FieldDataTypes::Date.new
    #   end
    sig { abstract.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
    def elasticsearch_mapping; end

    # Returns the names of the `Indexable::Processor::Base` subclasses that will be used to process Hydro events in
    # order to keep the Elasticsearch index for this field up to date.
    #
    # Any name that appears in this list must correspond to a real `Indexable::Processor::Base` subclass.
    #
    # EXAMPLE:
    #
    #   def register_processors
    #     ["MemexProjectColumn::Interface::Indexable::Processor::AccountRename"]
    #   end
    sig { abstract.returns(T::Array[String]) }
    def register_processors; end

    # Whether or not this field has fully implemented the Indexable interface, and so should be added to our
    # Elasticsearch index.
    #
    # This should typically return true, but when introducing a new field type it can be helpful to temporarily
    # return false as we build out support for that field type incrementally.
    sig { abstract.returns(T::Boolean) }
    def indexable?; end
  end

  mixes_in_class_methods(ClassMethods)

  # Returns the data that will be stored in Elasticsearch under this field for the given item.
  #
  # The value you return must be compatible with the return value of `elasticsearch_mapping`. Additionally, we use
  # the convention of defining an entry in the `Document::MemexProjectItem::Value` type alias for each field type,
  # so you will need to add to that alias if you are implementing a new field type. Finally, if this method returns
  # an array, then that array should be deterministically sorted (in order to ensure that we can reliably compare
  # documents generated at different times).
  #
  # This method should consider each of the possible values of the `content_type` attribute of the given item, in case
  # it needs to special case any of them.
  #
  # If this method encounters a race condition in which the data it would like to return unexpectedly does not exist,
  # it should raise `CanonicalDataMissingError`.
  #
  # EXAMPLE:
  #
  #   def elasticsearch_document(item)
  #     case item.content_type
  #     when "Issue", "PullRequest"
  #       return item.content.repository
  #     else
  #       nil
  #     end
  #   end
  sig { abstract.params(item: MemexProjectItem).returns(Elastomer::Interfaces::Document::MemexProjectItem::Value) }
  def elasticsearch_document(item); end

  # Use this hook to preload data so that subsequent calls to `elasticsearch_document` load data efficiently.
  #
  # Please see https://thehub.github.com/epd/engineering/products-and-services/dotcom/preloading-records/
  # to learn about preloading strategies that are appropriate to use when implementing this method.
  #
  # EXAMPLE:
  #
  #   Given these implementations:
  #
  #   def preload_elasticsearch_document_data(items)
  #     GitHub::PrefillAssociations.prefill_associations(items, :repository)
  #   end
  #
  #   def elasticsearch_document(item)
  #     Elastomer::Interfaces::Document::Repository.new(full_name: item.repository&.full_name)
  #   end
  #
  #   The framework will run code like this:
  #
  #   items = MemexProject.last.memex_project_items.to_a
  #   field = MemexProject.last.columns.find(&:repository?).to_field
  #   field.preload_elasticsearch_document_data(items)
  #   items.map { |item| field.elasticsearch_document(item) } # <-- This loop no longer makes any database queries ✨
  #
  sig { abstract.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items); end
end
