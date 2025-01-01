# typed: strict
# frozen_string_literal: true

class BusinessTeam < Team
  include T::Sig

  belongs_to :business
  validates_presence_of :business

  has_many :business_team_org_assignments, inverse_of: :business_team
  destroy_dependents_in_background :business_team_org_assignments

  validates :name, uniqueness: { scope: :business_id, case_sensitive: false }
  validates :slug, uniqueness: { scope: :business_id, case_sensitive: true }

  has_many :selected_organizations,
    through: :business_team_org_assignments,
    source: :organization,
    foreign_key: :team_id

  enum :organization_selection_type, {
    disabled: 0,
    all: 1,
    selected: 2
  }, prefix: :org_assignment
  validates_inclusion_of :organization_selection_type, in: organization_selection_types.keys, message: "Invalid assignment type"

  validates_absence_of :organization_id

  default_scope { unscope(where: :organization_id) }

  sig { returns(T::Boolean) }
  def business_team?
    true
  end

  sig { params(business: T.nilable(Business)).returns(T::Boolean) }
  def self.enabled_for_enterprise?(business:)
    return false if business.nil?
    return false if EnterpriseTeam.enabled_for_organizations?(business: business)
    business.feature_enabled?(:business_teams)
  end

  sig { returns(T::Array[Integer]) }
  def organization_ids
    case organization_selection_type.to_sym
    when :all
      T.must(business).organization_ids
    when :selected
      selected_organization_ids
    else
      []
    end
  end

  # Task: Implement BusinessTeam#add_to_organizations and BusinessTeam#remove_from_organizations
  sig { params(org_ids: T::Array[Integer]).void }
  def add_to_organizations(org_ids:)
    # Sync all does not use BusinessTeamOrgAssignment, disabled means no orgs
    return unless org_assignment_selected?

    org_ids.compact!
    org_ids = T.must(business).organizations.where(id: org_ids).ids
    return if org_ids.empty?

    new_org_ids = org_ids - organization_ids
    batch = new_org_ids.map do |org_id|
      {
        team_id: id,
        organization_id: org_id,
      }
    end
    with_write { BusinessTeamOrgAssignment.insert_all(batch) }
  end

  sig { params(org_ids: T::Array[Integer]).void }
  def remove_from_organizations(org_ids:)
    return unless org_assignment_selected?

    with_write { BusinessTeamOrgAssignment.where(team_id: id, organization_id: org_ids).destroy_all }
  end

  sig { params(candidate: String).returns(T::Boolean) }
  private def any_conflicting_slugs?(candidate)
    scope = self.class.where(business_id: business_id, slug: candidate)
    scope = scope.where("id <> ?", id) unless new_record?

    scope.any?
  end

  # Public: Returns a uniquely identifiable slug for an Enterprise / Team combination
  #
  # TODO: This is a placeholder override for now since we don't have product specs yet, and otherwise can not
  # initialize an org-less team.
  #
  # Returns the slug
  sig { returns(String) }
  def combined_slug
    "/#{slug}"
  end
  alias_method :to_s, :combined_slug

  # Public: Returns either the User who created the team, or the Business that the team
  # belongs to.
  #
  # This method is mostly going to be used for front-end display purposes.
  sig { returns(T.nilable(T.any(User, Business))) }
  def creator
    super || business
  end
end
