# typed: false # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Sorbet does not handle ActiveSupport::Concern well, so we need to disable strictness here

# Base class for external property namespaces. External properties allow third-party providers to
# flow their existing metadata into our system.
module CustomPropertiesCore
  module ExternalProperties
    module NamespaceBase
      extend ActiveSupport::Concern
      extend T::Helpers
      include Instrumentation::Model
      include IPropertyNamespace

      abstract!

      sig { abstract.returns(NamespaceBase) }
      def destroy!; end

      sig { abstract.returns(T::Boolean) }
      def present?; end

      sig { abstract.params(attributes: T.untyped).returns(NamespaceBase) }
      def update!(attributes); end

      included do
        has_many :external_property_definitions, class_name: self.definition_class_name, foreign_key: "namespace_id", dependent: :destroy, inverse_of: :namespace

        after_create_commit :instrument_create
        after_update_commit :instrument_update, if: :saved_changes?
        after_destroy :instrument_destroy

        validates :source_type, presence: true
        validates :source_id, presence: true
        validates :integration_id, presence: true
        validates_length_of :display_name, minimum: 1, maximum: Public::MAX_NAMESPACE_DISPLAY_NAME_LENGTH
        validates_format_of :display_name, with: Public::NAMESPACE_DISPLAY_NAME_VALID_CHARS_REGEX
        validate :display_name_not_reserved

        # Returns namespaces defined at the given source level only
        scope :defined_by, ->(source) do
          source = T.cast(source, PropertySource)
          source_type = source.is_a?(::Business) ? :business : :org
          where(source_id: source.id, source_type: source_type)
        end

        # Returns all namespaces for the source and its parent levels
        scope :for_source, ->(source) do
          source = T.cast(source, PropertySource)

          if source.is_a?(::Business)
            self.defined_by(source)
          else
            business = source.business
            relation = self.defined_by(source)
            relation = relation.or(self.defined_by(business)) if business.present?

            relation
          end
        end

        scope :for_org_ids, ->(org_ids) { where(source_id: org_ids, source_type: :org) }
        scope :for_business_ids, ->(business_ids) { where(source_id: business_ids, source_type: :business) }

        enum :source_type, {
          org: 0,
          business: 1,
        }, suffix: true

        batch_method(:source) do |namespaces|
          org_namespaces, business_namespaces = namespaces.partition { |namespace| namespace.source_type == "org" }

          org_sources = Organization.where(id: org_namespaces.map(&:source_id)).index_by(&:id)
          business_sources = Business.where(id: business_namespaces.map(&:source_id)).index_by(&:id)

          namespaces.to_h do |namespace|
            source = namespace.org_source_type? ? org_sources[namespace.source_id] : business_sources[namespace.source_id]
            [namespace, source]
          end
        end
      end

      sig { returns(ActiveRecord::Associations::CollectionProxy) }
      def definitions
        external_property_definitions
      end

      sig { params(params: T.untyped).void }
      def initialize(params)
        source = T.cast(params&.delete(:source), T.nilable(PropertySource))
        if source&.is_a?(::Organization) || source&.is_a?(::Business)
          @source = T.let(source, T.nilable(PropertySource))
          params[:source_id] = @source&.id
          params[:source_type] = @source&.is_a?(::Business) ? :business : :org
        end

        super(params)
      end

      private

      sig { void }
      def display_name_not_reserved
        if display_name.present? && Public::RESERVED_NAMESPACE_DISPLAY_NAMES.include?(display_name.downcase)
          errors.add(:display_name, "is reserved and cannot be used")
        end
      end

      sig { void }
      def instrument_create
        instrument :create
      end

      sig { void }
      def instrument_destroy
        instrument :destroy
      end

      sig { void }
      def instrument_update
        payload = changes_payload
        instrument :update, payload if payload
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def event_payload
        owner_hash = business_source_type? ? { business: source } : { org: source }

        {
          namespace_id: id,
          integration_id: integration_id,
          display_name: display_name,
        }.merge(owner_hash)
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def changes_payload
        {
          old_display_name: previous_changes["display_name"]&.first,
        } if previous_changes["display_name"]&.first
      end
    end
  end
end
