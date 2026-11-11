# typed: true
# frozen_string_literal: true

# Shared logic for decorating Copilot memories with billing entity information so
# both user-scoped (Settings::Copilot::MemoryController) and repository-scoped
# (Repos::CopilotSettings::MemoryController) controllers render a consistent payload
# for the copilot-memory React page.
module Copilot::MemoryBillingEntityDecoration
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  private

  # Decorates each memory hash with billing_entity information based on the
  # billingOrganizationId / billingEnterpriseId values returned by sweagentd.
  # Performs a single bulk load per entity type to avoid N+1 queries.
  # Memories without billing IDs (or referencing deleted entities) get billing_entity: nil.
  # When both an organization and an enterprise are available, both are included so callers have more to work with.
  # On unexpected failure (e.g. DB outage during the bulk load) every memory is returned with billing_entity: nil so the memories page still renders.
  def decorate_memories_with_billing_entity(memories, log_context: {})
    return memories if memories.empty?

    org_ids = memories.filter_map { |m| m["billingOrganizationId"]&.to_i }.reject(&:zero?).uniq
    ent_ids = memories.filter_map { |m| m["billingEnterpriseId"]&.to_i }.reject(&:zero?).uniq

    orgs_by_id = org_ids.any? ? Organization.where(id: org_ids).index_by(&:id) : {}
    businesses_by_id = ent_ids.any? ? Business.where(id: ent_ids).index_by(&:id) : {}

    memories.map do |memory|
      org_id = memory["billingOrganizationId"]&.to_i
      ent_id = memory["billingEnterpriseId"]&.to_i

      organization = orgs_by_id.fetch(org_id, nil)
      business = businesses_by_id.fetch(ent_id, nil)

      result = Copilot::BillingEntityResolver::Result.new(business:, organization:)
      memory.merge("billing_entity" => build_billing_entity_hash_from_resolver(result))
    end
  rescue StandardError => e
    GitHub.logger.warn("Copilot memory: failed to decorate memories with billing entity", log_context.merge(
      "gh.error.message" => e.message,
      "gh.error.class" => e.class.name,
    ))
    GitHub.dogstats.increment("copilot_memory.decorate", tags: ["result:error"])
    memories.map { |m| m.merge("billing_entity" => nil) }
  end

  def build_billing_entity_hash_from_resolver(result)
    business = result.business
    organization = result.organization

    return nil if organization.nil? && business.nil?

    {
      has_organization: !organization.nil?,
      has_enterprise: !business.nil?,
      organization: organization && {
        id: organization.id,
        display_name: result.organization_display_name,
        login: organization.display_login,
        manage_billing_url: settings_org_billing_path(organization),
      },
      enterprise: business && {
        id: business.id,
        display_name: result.business_display_name,
        login: business.slug,
        manage_billing_url: settings_billing_enterprise_path(business),
      },
    }
  end
end
