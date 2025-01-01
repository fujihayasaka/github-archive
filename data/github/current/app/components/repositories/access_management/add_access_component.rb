# typed: true
# frozen_string_literal: true

class Repositories::AccessManagement::AddAccessComponent < ApplicationComponent
  include Repos::AccessManagementDependency
  include EnterpriseManagedUsersHelper

  attr_reader :repository, :add_type

  def initialize(repository:, add_type:)
    @repository = repository
    @add_type = add_type
  end

  def show_seat_info?
    organization = repository&.organization
    organization && !is_user_fork_of_private_org_repo? && organization.member?(current_user) && organization.plan.per_seat? && !organization.has_unlimited_seats?
  end

  def seats_left
    organization.total_available_seats
  end

  def self_serve_billing_org?
    organization.business.present? && organization.business.can_self_serve?
  end

  # Public: Should we display a warning about requirements to invite outside collaborators
  def display_outside_collab_warning?
    (!repository.is_enterprise_managed? && !repository.organization&.business&.emu_repository_collaborators_enabled?) &&
    (repository.cannot_invite_outside_collaborators?(current_user) && add_type != "team")
  end

  def outside_collab_warning_text
    if organization.enterprise_admins_only_can_invite_outside_collaborators?
      "#{outside_collaborators_verbiage(organization).capitalize} can only be invited by enterprise owners."
    else
      "#{outside_collaborators_verbiage(organization).capitalize} can only be invited by organization owners."
    end
  end

  def show_individual_role_select?
    repository.in_organization?
  end

  private

  memoize def organization
    repository&.organization
  end
end
