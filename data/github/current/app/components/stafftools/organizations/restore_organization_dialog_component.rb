# typed: true
# frozen_string_literal: true

class Stafftools::Organizations::RestoreOrganizationDialogComponent < ApplicationComponent
  sig { returns Organization }
  attr_reader :organization

  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns String }
  attr_reader :return_to

  def initialize(organization:, business: nil, return_to:)
    @organization = organization
    @business = business
    @return_to = return_to
  end

  def render_enterprise_team_assignment_warning?
    biz = Business.find_by(id: organization.business_id) if organization.business_id.to_i > 0
    biz &&
      biz.business_teams.where(organization_selection_type: :selected).any?
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if organization.belongs_to_a_soft_deleted_business?
    true
  end

  memoize def disabled?
    !helpers.stafftools_action_authorized?(controller: Stafftools::Users::UndeletesController, action: :create)
  end
end
