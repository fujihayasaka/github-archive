# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

# Base class for external property definitions. External properties allow third-party providers to
# flow their existing metadata into our system.
# External property definitions always have a string value type and are scoped by namespace.
module CustomPropertiesCore
  module ExternalProperties
    module DefinitionBase
      extend ActiveSupport::Concern
      extend T::Helpers
      include Instrumentation::Model
      include IPropertyDefinition

      abstract!

      sig { abstract.returns(DefinitionBase) }
      def destroy!; end

      sig { abstract.returns(T::Boolean) }
      def present?; end

      sig { abstract.params(attributes: T.untyped).returns(DefinitionBase) }
      def update!(attributes); end

      included do
        belongs_to :namespace, class_name: self.namespace_class_name, foreign_key: :namespace_id, inverse_of: :external_property_definitions
        has_many :external_property_values, class_name: self.value_class_name, foreign_key: "definition_id", dependent: :delete_all, inverse_of: :definition

        after_create_commit :instrument_create
        after_destroy :instrument_destroy

        validates :namespace_id, presence: true

        validates_format_of :property_name, with: Public::NAME_VALID_CHARS_REGEX
        validates_length_of :property_name, minimum: 1, maximum: Public::MAX_PROPERTY_NAME_LENGTH

        scope :for_namespace, ->(namespace) { where(namespace_id: namespace.id) }
        scope :for_namespace_ids, ->(namespace_ids) { where(namespace_id: namespace_ids) }

        batch_method(:source) do |definitions|
          GitHub::PrefillAssociations.prefill_associations(definitions, :namespace)
          namespaces = definitions.map(&:namespace)
          GitHub::PrefillAssociations.prefill_batch_method(namespaces, :source)

          definitions.to_h do |definition|
            source = definition.namespace.source
            [definition, source]
          end
        end
      end

      sig { returns(ActiveRecord::Associations::CollectionProxy) }
      def values
        external_property_values
      end

      # Some IPropertyDefinition fields need to be loaded from the namespace object

      sig { override.returns(Integer) }
      def source_id
        namespace.source_id
      end

      sig { override.returns(String) }
      def source_type
        namespace.source_type
      end

      sig { override.returns(T::Boolean) }
      def business_source_type?
        namespace.business_source_type?
      end

      sig { override.returns(T::Boolean) }
      def org_source_type?
        namespace.org_source_type?
      end

      sig { override.returns(String) }
      def type
        "external"
      end

      # External properties do not support the following IPropertyDefinition fields.
      # Defaults are provided to allow these definitions to be used within common properties logic.

      sig { override.returns(T::Boolean) }
      def required
        false
      end

      sig { override.returns(T.nilable(String)) }
      def description
        nil
      end

      sig { override.returns(T.nilable(PropertyValue)) }
      def default_value
        nil
      end

      sig { override.returns(String) }
      def values_editable_by
        "no_actors"
      end

      # Returning nil insead of raising NotImplementedError so that we can pass these definitions to
      # the existing CustomPropertiesValidator
      sig { override.returns(T.nilable(String)) }
      def regex
        nil
      end

      # Returning nil instead of raising NotImplementedError so that we can pass these definitions to
      # the existing CustomPropertiesValidator
      sig { override.returns(T.nilable(T::Array[String])) }
      def allowed_values
        nil
      end

      # External properties are always strings, so value_type is hardcoded.
      sig { override.returns(String) }
      def value_type
        "string"
      end

      sig { override.returns(T::Boolean) }
      def string_value_type?
        true
      end

      sig { override.returns(T::Boolean) }
      def true_false_value_type?
        false
      end

      sig { override.returns(T::Boolean) }
      def single_select_value_type?
        false
      end

      sig { override.returns(T::Boolean) }
      def multi_select_value_type?
        false
      end

      sig { override.returns(T::Boolean) }
      def url_value_type?
        false
      end

      sig { override.returns(T::Boolean) }
      def actor_value_type?
        false
      end

      private

      sig { void }
      def instrument_create
        instrument :create
      end

      sig { void }
      def instrument_destroy
        instrument :destroy
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def event_payload
        owner_hash = business_source_type? ? { business: source } : { org: source }

        {
          definition_id: id,
          namespace: namespace.display_name,
          property_name: property_name,
        }.merge(owner_hash)
      end
    end
  end
end
