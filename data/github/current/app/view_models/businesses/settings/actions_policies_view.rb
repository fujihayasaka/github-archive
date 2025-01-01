# typed: true
# frozen_string_literal: true

class Businesses::Settings::ActionsPoliciesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :query, :current_page

  PAGE_SIZE = 25

  ALL_ENTITIES = ::Configurable::ActionsAccess::ALL_ENTITIES
  SELECTED_ENTITIES = ::Configurable::ActionsAccess::SELECTED_ENTITIES
  DISABLED = Actions::PolicyUpdater::DISABLED

  def action_policy_list
    [
      GitHub::Menu::ButtonComponent.new(
        text: "Enable for all organizations",
        description: "All organizations, including any created in the future, may use GitHub Actions.",
        replace_text: "Enable for all organizations",
        checked: business.actions_enabled_for_all_entities?,
        name: "policy",
        value: ALL_ENTITIES,
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        text: "Enable for specific organizations",
        description: "Only specifically-selected organizations may use GitHub Actions.",
        replace_text: "Enable for specific organizations",
        checked: selected_orgs_only?,
        name: "policy",
        value: SELECTED_ENTITIES,
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        text: "Disabled",
        description: "No organizations may use GitHub Actions.",
        replace_text: "Disabled",
        checked: business.actions_disabled?,
        name: "policy",
        value: DISABLED,
        type: "submit",
      ),
    ]
  end

  def show_org_list?
    selected_orgs_only?
  end

  def orgs
    return @orgs if defined?(@orgs)

    orgs = Organization.
      includes(business_membership: [:business]).
      where(business_organization_memberships: { business_id: business.id }).
      order(login: :asc)


    if query
      orgs = orgs.where("login LIKE :query", { query: "%#{query}%" })
    end

    @orgs = orgs.paginate(page: current_page, per_page: PAGE_SIZE)
  end

  def actions_allowed?(organization)
    allowed_orgs.include?(organization.id)
  end

  private

  def selected_orgs_only?
    business.actions_enabled_for_selected_entities?
  end

  def allowed_orgs
    return @_allowed_orgs if defined?(@_allowed_orgs)
    @_allowed_orgs = business.actions_allowed_entities
  end
end
