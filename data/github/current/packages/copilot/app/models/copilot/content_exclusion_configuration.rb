# typed: strict
# frozen_string_literal: true

module Copilot
  class ContentExclusionConfiguration < ApplicationRecord::Copilot

    include GitHub::Memoizer
    include Copilot::ContentExclusion::RulesResolver

    self.table_name = "copilot_ignores"
    self.strict_loading_by_default = true

    DOC_CHAR_LIMIT = 1_000_000

    belongs_to :resource, polymorphic: true, strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :updated_by, class_name: "::User", foreign_key: "updated_by_id", strict_loading: false
    # rubocop:enable Rails/InverseOf
    belongs_to :organization, class_name: "::Organization", strict_loading: false

    validates :resource, presence: true
    validates :resource_type, inclusion: { in: %w[Repository Organization Business] }

    validates :document, length: { maximum: DOC_CHAR_LIMIT }
    validates :document, uniqueness: {
      scope: [:resource_id, :resource_type], \
      message: "A document for this resource already exists."
    }
    validate :ensure_valid_document

    before_validation :ensure_organization_or_business_relationship_exists

    after_commit :instrument_update, on: [:create, :update]

    scope :for_organization, ->(entities) { where(resource_id: entities.respond_to?(:pluck) ? entities.pluck(:id) : entities.id, resource_type: "Organization") }
    scope :for_repository, ->(entities) { where(resource_id: entities.respond_to?(:pluck) ? entities.pluck(:id) : entities.id, resource_type: "Repository") }
    scope :for_business, ->(entities) { where(resource_id: entities.respond_to?(:pluck) ? entities.pluck(:id) : entities.id, resource_type: "Business") }

    scope :for_organization_ids, ->(ids) { where(resource_id: ids, resource_type: "Organization") }
    scope :for_repository_ids, ->(ids) { where(resource_id: ids, resource_type: "Repository") }
    scope :for_business_ids, -> (ids) { where(resource_id: ids, resource_type: "Business") }

    scope :with_organization_ids, -> (ids) { where(organization_id: ids) }
    scope :with_business_or_organization_ids, -> (business_ids, organization_ids, neighbor_organization_ids) do
      where(resource_id: business_ids, resource_type: "Business").or(
        where(organization_id: organization_ids)
      ).or(
        where(organization_id: neighbor_organization_ids, resource_type: "Repository")
      )
    end

    scope :by_resource, -> { order(:resource_type, :resource_id) }
    scope :with_document, -> { where.not(document: [nil, ""]) }

    sig { void }
    def ensure_valid_document
      if document.present? && document.to_s.length > DOC_CHAR_LIMIT
        errors.add(:document, "Document size is too large, maximum is #{DOC_CHAR_LIMIT} characters")
        return
      end

      rules = parsed_document&.validate
      return unless rules.present?

      return if rules.ok?
      errors.add(:document, rules.error.message)
    end

    sig { void }
    def ensure_organization_or_business_relationship_exists
      return unless self.organization_id.nil?

      case self.resource_type
      when "Business"
        self.organization_id = nil
      when "Organization"
        self.organization_id = resource&.id
      when "Repository"
        owner = resource.owner
        self.organization_id = owner.id if owner.is_a?(::Organization)
      end
    end

    sig { returns(T.nilable(Copilot::ContentExclusion::Document)) }
    memoize def parsed_document
      return unless document.present?
      document_parser_class = case resource_type
      when "Business", "Organization"
        Copilot::Organizations::ContentExclusionDocument
      when "Repository"
        Copilot::Repositories::ContentExclusionDocument
      end

      allow_text_based_rules = organization&.feature_enabled?(:copilot_allow_text_based_content_exclusions) ||
        business&.feature_enabled?(:copilot_allow_text_based_content_exclusions) ||
        false
      T.must(document_parser_class).new(document, allow_text_based_rules:)
    end

    sig { returns(T.nilable(::Business)) }
    def business
      return unless resource_type == "Business"
      resource
    end

    private

    sig { void }
    def instrument_update
      Copilot::Instrumenter.instrument_content_exclusion_changed(resource, updated_by, document)
    end
  end
end
