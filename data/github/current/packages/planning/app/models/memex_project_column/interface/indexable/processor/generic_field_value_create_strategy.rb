# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  # This module replaces the typical `Indexable::Processor::Base` interface with a simpler one. Rather than
  # implementing the five required methods of that interface, this module requires only one: `field_class`.
  #
  # This module should be included in any `Indexable::Processor::Base` base class that is responsible for processing
  # create events for a generic field. For the definition of a generic field, see:
  # https://github.com/github/projects-backend/blob/main/docs/initiatives/memex-without-limits/glossary.md#generically-typed-field
  #
  # This module should **not** be used for processors that are registered with a special field.
  #
  # For an example use of this module, please see `MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueCreate`
  module GenericFieldValueCreateStrategy
    extend T::Helpers
    include GitHub::Memoizer
    include GenericFieldProcessorHelpers

    abstract!
    requires_ancestor { MemexProjectColumn::Interface::Indexable::Processor::Base }

    # Processors that include this module must declare the class of the field that they are processing values for.
    #
    # This is necessary because generic processors operate on `MemexProjectColumnValueCreate` messages, which
    # are emitted for every field type. We use the result of this method internally to filter out messages that were
    # emitted for other field types.
    #
    # EXAMPLE:
    #
    #   def field_class
    #     MemexProjectColumn::Field::SingleSelect
    #   end
    sig { abstract.returns(T.class_of(MemexProjectColumn::Field::Base)) }
    def field_class; end

    sig { returns(T.nilable(Symbol)) }
    def dependent_mysql_replication_cluster
      MemexProjectColumnValue.cluster_name
    end

    sig { returns(T::Boolean) }
    def valid_message?
      return false if project_id.blank? || item_id.blank? || field_id.blank?

      message.dig(:project_column, :data_type) == field_class.data_type.to_s
    end

    sig { returns(T::Boolean) }
    def matching_elasticsearch_documents?
      response = index.docs.get(
        id: item_id,
        routing: project_id,
        _source: false,
        type: document_type
      )
      response["found"] == true
    end

    sig { returns(T::Boolean) }
    def canonical_data_present?
      model = memex_project_column_value
      model.present? && model.memex_project_column.present? && model.memex_project_item.present?
    end

    sig do
      params(es_client: Search::Memex::Client)
      .returns(Elastomer::Interfaces::Api::Update::Response)
    end
    def update(es_client)
      body = Elastomer::Interfaces::Api::Update::Request::Body.new(
        script: field.elasticsearch_field_value_update_script(T.must(project_item))
      )
      params = Elastomer::Interfaces::Api::Update::Request::Params.new(
        id: T.must(item_id),
        routing: project_id,
      )
      es_client.update(body, params)
    end

    sig { returns(T::Array[Integer]) }
    def project_ids_to_resync_on_failure
      [T.must(project_id)]
    end

    sig { returns(T::Array[Base::ObjectWithGlobalRelayId]) }
    def updated_models
      if (model = memex_project_column_value)
        item = T.must(model.memex_project_item)
        field = T.must(model.memex_project_column).to_field
        [item, field]
      else
        []
      end
    end
  end
end
