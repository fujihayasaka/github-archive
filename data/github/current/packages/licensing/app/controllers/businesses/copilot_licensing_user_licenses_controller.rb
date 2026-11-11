# typed: true
# frozen_string_literal: true

class Businesses::CopilotLicensingUserLicensesController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_enterprise_copilot_licensing_enabled
  before_action :ensure_can_assign_copilot_to_business_users
  before_action :ensure_business_has_copilot_all_members_flag_enabled

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  allow_verified_fetch only: [:index]

  sig { void }
  def index
    user_id = params[:id].to_i
    user = User.find_by(id: user_id)
    return render_404 unless this_business.unaffiliated_member?(user)
    user = T.must(user)

    # Let's grab the copilot seats for this user that are tied to this business
    # There will be as many org seats as there are orgs in the business that have assigned a license to this user
    org_seats = Copilot::Seat.joins(:seat_assignment)
        .where(organization_id: this_business.organization_ids)
        .where(assigned_user_id: user.id)
        .where(copilot_seat_assignments: { access_revoked_at: nil })

    # For each org seat, if there's a pending cancellation date, then we need to
    # see if there are any other org seat assignments without a cancellation date
    # that apply to the user. If so, show that seat assignment to the user, as that's
    # what will take over once the current seat assignment takes over.
    org_seat_assignments = []

    org_seats.each do |seat|
      if seat.pending_cancellation_date.present?
        other_active_assignment = active_assignment_for_org_and_user(seat.owner_id, user)
        if other_active_assignment.present?
          org_seat_assignments << other_active_assignment
          next
        end
      end
      org_seat_assignments << seat.seat_assignment
    end

    # There will be either 0 or 1 direct business->user assigned seat assignment
    direct_assignment_for_user = Copilot::SeatAssignment
      .where(owner: this_business)
      .where(assignable_type: "User")
      .where(assignable_id: user.id)
      .where(access_revoked_at: nil)

    all_bt_assignments = Copilot::SeatAssignment
      .business_team_assignments(this_business)
      .where(access_revoked_at: nil)
    bt_assignments_for_user = all_bt_assignments.select { |assignment| assignment.includes_user?(user) }

    all_assignments_for_user = org_seat_assignments + direct_assignment_for_user + bt_assignments_for_user

    formatted_assignments = []
    all_assignments_for_user.each do |assignment|
      assignment_hash = build_assignment_hash(T.must(assignment))
      formatted_assignments << assignment_hash
    end

    formatted_assignments.sort_by! do |assignment|
      assignment[:planType] == "enterprise" ? 0 : 1
    end

    render json: {
      assignments: formatted_assignments
    }
  end

  private

  sig { void }
  def ensure_can_assign_copilot_to_business_users
    render_404 unless this_business.can_assign_copilot_to_business_users?
  end

  sig { void }
  def ensure_business_has_copilot_all_members_flag_enabled
    render_404 unless this_business.feature_flag_enabled?(:copilot_all_members_licensing_list, default: false)
  end

  sig { params(assignment: Copilot::SeatAssignment).returns(T::Hash[Symbol, T.any(Integer, String, NilClass)]) }
  def build_assignment_hash(assignment)
    if assignment.owner_type == "Organization"
      owner_display_type = "Organization"
      display_name_for_assignment_owner = assignment.owner.name
      plan = Copilot::Organization.new(assignment.owner).copilot_plan
      owner_url = user_path(assignment.owner)
    else
      plan = "business"
      if assignment.assignable_type == "BusinessTeam"
        display_name_for_assignment_owner = assignment.assignable.name
        owner_display_type = "BusinessTeam"
        owner_url = enterprise_team_path(this_business.slug, assignment.assignable.slug, only_path: true)
      else
        display_name_for_assignment_owner = assignment.owner.slug
        owner_display_type = "Business"
        owner_url = enterprise_url(this_business.slug)
      end
    end

    {
      id: assignment.id,
      ownerDisplayType: owner_display_type,
      ownerDisplayName: display_name_for_assignment_owner,
      ownerUrl: owner_url,
      expirationDate: assignment.pending_cancellation_date,
      planType: plan,
    }
  end

  sig { params(organization_id: Integer, user: User).returns(T.nilable(Copilot::SeatAssignment)) }
  def active_assignment_for_org_and_user(organization_id, user)
    Copilot::SeatAssignment
      .where(organization_id: organization_id)
      .where(assignable_type: %w[Team Organization User])
      .where(pending_cancellation_date: nil)
      .where(access_revoked_at: nil)
      .find { |assignment| assignment.includes_user?(user) }
  end
end
