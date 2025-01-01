# typed: true
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::GhasAvailabilityOrgListComponent < ApplicationComponent

  attr_reader :business, :query

  PAGE_SIZE = 25
  TEST_SELECTOR = "businesses-policies-security-analysis-ghas-availability-org-list"

  def initialize(business:, query:, page:)
    @business = business
    @query = query
    @page = page
  end

  def advanced_security_access_allowed?(organization)
    allowed_orgs.include?(organization.id)
  end

  def bulk_edit_menu_items
    [
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "Available",
        name: "org_ghas_availability",
        value: "available",
        description: "GitHub Advanced Security is available for all repositories within this organization.",
        replace_text: "Available",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "Not available",
        name: "org_ghas_availability",
        value: "not_available",
        description: "GitHub Advanced Security won’t be available for repositories within this organization.",
        replace_text: "Not available",
        type: "submit",
      ),
    ]
  end

  private

  memoize def allowed_orgs
    business.advanced_security_access_allowed_entities
  end

  memoize def orgs
    orgs = Organization.
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
