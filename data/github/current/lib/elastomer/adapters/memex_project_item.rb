# typed: strict
# frozen_string_literal: true

module Elastomer::Adapters
  class MemexProjectItem < ::Elastomer::Adapter
    include GitHub::Memoizer

    class CanonicalDataMissingError < StandardError; end

    sig { returns(String) }
    def self.index_name
      "MemexProjectItems"
    end

    sig { returns(T.any(Symbol, String)) }
    def self.mysql_cluster
      ::MemexProjectItem.cluster_name
    end

    sig { returns(T.nilable(::MemexProjectItem)) }
    memoize def model
      return @model if defined? @model
      @model = T.let(memex_project_item, T.nilable(::MemexProjectItem))
    end

    sig { returns(Integer) }
    def document_routing
      T.must(model).memex_project_id
    end

    sig { returns(T::Boolean) }
    def project_exists?
      return false if model.nil? || project.nil?

      !!(
        T.must(model).memex_project.present? &&
        !T.must(project).deleted_at
      )
    end

    sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
    def content_elasticsearch_document
      unless content_doc = model&.content&.memex_content_elasticsearch_document
        raise CanonicalDataMissingError
      end
      content_doc
    end

    sig { returns(T::Boolean) }
    def content_exists?
      return false if model.nil?
      !!T.must(model).content.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    memoize def to_hash
      raise Elastomer::ModelMissing if model.nil?

      # Check that the parent project still exists and hasn't been soft deleted.
      return unless content_exists? && project_exists?

      document.to_hash
    end

    sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::Root) }
    memoize def document
      project_item = T.must(model)

      cluster = Elastomer.router.cluster_for_index(Elastomer.env.lookup_index(self))

      Elastomer::Interfaces::Document::MemexProjectItem::Root.new(
        cluster_on_8_plus: Elastomer.router.cluster_running_version_8_plus?(cluster),
        _id: document_id.to_s,
        _routing: document_routing,
        _type: document_type,
        content: content_elasticsearch_document,
        field_values: field_values(project_item),
        metadata: project_item.elasticsearch_metadata
      )
    end

    sig { params(item: ::MemexProjectItem).returns(T::Array[Elastomer::Interfaces::Document::MemexProjectItem::FieldValue]) }
    private def field_values(item)
      T.must(project).memex_project_columns.each_with_object([]) do |column, result|
        begin
          field = T.must(column.to_field)
          next if field.class.exclude_from_index?
          next unless value = field.elasticsearch_field_value(item)

          result << value
        rescue MemexProjectColumn::FieldDependency::MissingFieldImplementation
          # Ignore missing field implementations.
        end
      end
    end

    sig { returns(T.nilable(::MemexProject)) }
    memoize private def project
      return if model.nil?
      T.must(model).memex_project
    end

    sig { returns(T.nilable(::MemexProjectItem)) }
    memoize private def memex_project_item
      ::MemexProjectItem
        .includes({ memex_project: :memex_project_columns })
        .find_by(id: document_id)
    end
  end
end
