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

      sig do
        params(
          node_id_object: Object,
          name: String,
          display_name: String,
          description: String,
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
      def initialize(node_id_object:, name:, display_name:, description:, required: false, org_only: false, internal: false, supported_plan: nil, default_value: nil, apply_default_on_load: false, validator: nil, ui_control: nil, visibility_fn: nil, feature_flag: nil,
        min_ghes_version: nil, beta: false, beta_api_note: false, publish_api: nil, description_api: nil, ui_options: {}, aliases: [], transform_fn: nil)

        @node_id_object = node_id_object

        super(type: :node_id, name:, display_name:, description:, required:, internal:, org_only:, supported_plan:, default_value:, apply_default_on_load:,
        validator:, ui_control:, visibility_fn:, feature_flag:, min_ghes_version:, beta:, beta_api_note:, publish_api:, description_api:, aliases:, transform_fn:)

        raise "Expect 1 id and 1 type field" if node_id_object.fields.map(&:name).sort != %w[id type]
      end
    end
  end
end
