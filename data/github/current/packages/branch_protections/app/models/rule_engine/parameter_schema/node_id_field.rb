# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class NodeIdField < Field
      # A node id field will be used in the UI and GraphQL
      # while the nodde_id_object will be used for the REST API

      # A parameter schema object mapping a node id to a database id and type
      sig { returns(Object) }
      attr_reader :node_id_object

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :valid_types

      sig do
        params(
          node_id_object: Object,
          name: String,
          display_name: String,
          description: String,
          valid_types: T.nilable(T::Array[String]),
          required: T::Boolean,
          org_only: T::Boolean,
          internal: T::Boolean,
          supported_plan: T.nilable(String),
          default_value: T.untyped,
          apply_default_on_load: T::Boolean,
          validator: T.nilable(T.proc.params(arg0: T.untyped).returns(T::Boolean)),
          ui_control: T.nilable(String),
          visibility_fn: T.nilable(T.proc.params(arg0: T.untyped).returns(T::Boolean)),
          feature_flag: T.nilable(String),
          min_ghes_version: T.nilable(String),
          beta: T::Boolean,
          beta_api_note: T::Boolean,
          publish_api: T.nilable(String),
          description_api: T.nilable(String),
          ui_options: T::Hash[String, T.untyped],
          aliases: T::Array[String],
          transform_fn: T.nilable(T.proc.params(arg0: T.untyped).returns(T.untyped))
        ).void
      end
      def initialize(node_id_object:, name:, display_name:, description:, valid_types: nil, required: false, org_only: false, internal: false, supported_plan: nil, default_value: nil, apply_default_on_load: false, validator: nil, ui_control: nil, visibility_fn: nil, feature_flag: nil,
        min_ghes_version: nil, beta: false, beta_api_note: false, publish_api: nil, description_api: nil, ui_options: {}, aliases: [], transform_fn: nil)
        @node_id_object = node_id_object
        @valid_types = valid_types

        super(type: :node_id, name:, display_name:, description:, required:, internal:, org_only:, supported_plan:, default_value:, apply_default_on_load:,
        validator:, ui_control:, visibility_fn:, feature_flag:, min_ghes_version:, beta:, beta_api_note:, publish_api:, description_api:, aliases:, transform_fn:)

        raise "Expect 1 id and 1 type field" if node_id_object.fields.map(&:name).sort != %w[id type]
      end

      def graphql_type
        "ID"
      end

      def validate_parameters(context, param_value)
        errors = super
        return errors unless param_value.is_a?(String) && param_value.present?

        result = begin
          Platform::Helpers::GlobalId.parse(param_value)
        rescue Platform::Errors::NotFound
          errors << { error_code: :invalid, message: "Invalid node ID format" }
          return errors
        end

        if (types = valid_types) && !types.include?(result&.type)
          errors << { error_code: :invalid, message: "Invalid node type. Expected one of #{types.join(", ")}" }
        end
        errors
      end

      sig { params(node_ids: T::Enumerable[String]).returns(T::Set[String]) }
      def self.valid_node_ids(node_ids)
        valid_node_ids = Set.new
        parsed = node_ids.map do |node_id|
          result = begin
            Platform::Helpers::GlobalId.parse(node_id)
          rescue Platform::Errors::NotFound
            nil
          end
          [node_id, result]
        end
        ids_by_type = parsed.group_by { |_, result| result&.type }
        Promise.all(ids_by_type.filter_map do |type, results|
          if type && results.any?
            node_ids_by_id = results.map { |node_id, result| [result&.id&.to_i, node_id] }.to_h

            klass = type.safe_constantize
            next unless klass && klass < ActiveRecord::Base

            valid_ids = klass.where(id: node_ids_by_id.keys).pluck(:id)
            valid_ids.each do |id|
              valid_node_ids << node_ids_by_id[id].to_s
            end
          end
        end).sync
        valid_node_ids
      end
    end
  end
end
