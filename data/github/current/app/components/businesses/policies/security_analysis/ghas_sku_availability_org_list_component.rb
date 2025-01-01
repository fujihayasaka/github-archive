# typed: true
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::GhasSKUAvailabilityOrgListComponent < ApplicationComponent

  attr_reader :business, :query

  PAGE_SIZE = 25
  TEST_SELECTOR = "businesses-policies-security-analysis-ghas-sku-availability-org-list"

  def initialize(business:, query:, page:)
    @business = business
    @query = query
    @page = page
  end

  def bulk_edit_menu_items
    [
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "All plans",
        name: "org_ghas_sku_availability",
        value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL,
        description: "Organization can enable all Advanced Security features and consume Secret Protection and Code Security licenses.",
        replace_text: "All plans",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "Secret Protection only",
        name: "org_ghas_sku_availability",
        value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY,
        description: "Organization can only enable Secret Protection features and consume Secret Protection licenses.",
        replace_text: "Secret Protection only",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "Code Security only",
        name: "org_ghas_sku_availability",
        value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY,
        description: "Organization can only enable Code Security features and consume Code Security licenses.",
        replace_text: "Code Security only",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: render(Primer::Beta::Text.new(tag: :span, color: :danger).with_content("Not available")),
        name: "org_ghas_sku_availability",
        value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE,
        description: "Organization will not be able to enable any Advanced Security features.",
        replace_text: "Not available",
        type: "submit",
      ),
    ]
  end

  private

  memoize def policies
    business.advanced_security_access_entity_policies
  end

  def organization_policy(organization)
    policy = policies[organization.id]
    policy = Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE if policy.nil?
    policy
  end

  memoize def orgs
    orgs = Organization.
      active.
      includes(business_membership: [:business]).
      where(business_organization_memberships: { business_id: business.id }).
      order(login: :asc)

    if query
      orgs = orgs.where("login LIKE :query", { query: "%#{query}%" })
    end

    # Tap :to_a method of paginated collection to trigger eager loading
    # to avoid multiple queries in the component.
    orgs.paginate(page: @page, per_page: PAGE_SIZE).tap(&:to_a)
  end
end
