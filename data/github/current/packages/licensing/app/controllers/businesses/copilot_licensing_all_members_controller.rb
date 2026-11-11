# typed: strict
# frozen_string_literal: true

class Businesses::CopilotLicensingAllMembersController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_enterprise_copilot_licensing_enabled
  before_action :ensure_can_assign_copilot_to_business_users
  before_action :ensure_business_has_copilot_all_members_flag_enabled

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
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

  USERS_PER_PAGE = 20

  sig { void }
  def index
    query = params[:query].presence
    page = params[:page] || 1
    users = []

    member_ids = this_business.filtered_members(
      current_user,
      business_user_accounts_query: true,
      include_unaffiliated: true,
      query: query
    ).where.not(user_id: nil).pluck(:user_id) if query

    if query && member_ids.empty?
      return render json: {
        withCopilotAccess: users
      }
    end

    all_seats = Copilot::Seat.all_active_seats_in_business(this_business)
    assigned_user_ids = all_seats.pluck(:assigned_user_id).uniq

    if query
      assigned_user_ids = assigned_user_ids & member_ids
    end

    total_count = assigned_user_ids.count
    user_id_batch = assigned_user_ids.paginate(page: page, per_page: USERS_PER_PAGE)
    user_batch = User.where(id: user_id_batch)
    user_batch.each do |user|
      user_hash = build_user_hash(user)
      users << user_hash
    end

    render json: {
      withCopilotAccess: users,
      totalCount: total_count
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

  sig { params(user_object: T.nilable(User)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def build_user_hash(user_object)
    return if user_object.nil?

    user_url = user_path(user_object)
    avatar_url = user_object.primary_avatar_url

    if all_assignments_for_user_expiring?(user_object)
      license_expiration_date = (this_business.next_metered_billing_cycle_starts_at - 1.day).in_time_zone("UTC").to_date
    else
      license_expiration_date = nil
    end

    user_hash = {
      login: user_object.display_login,
      name: user_object.safe_profile_name,
      id: user_object.id,
      userUrl: user_url,
      avatarUrl: avatar_url,
      licenseExpirationDate: license_expiration_date,
    }
  end

  sig { params(user: User).returns(T::Boolean) }
  def all_assignments_for_user_expiring?(user)
    # Cheapest thing to do is to check if any of the copilot seats
    # that the user has in this business have no set pending cancellation date.
    # That should allow us to return early in the majority of cases
    Copilot::Seat.all_active_seats_in_business(this_business).where(assigned_user_id: user.id).each do |seat|
      return false if seat.pending_cancellation_date.nil?
    end

    # Now, if all the user's seat(s) are pointing to seat assignments with a set pending cancellation date,
    # we need to find other seat assignments that the seat could be repointed to, and see if those
    # don't have a set pending cancellation date
    direct_org_seat_assignments = Copilot::SeatAssignment
      .where(organization_id: this_business.organization_ids)
      .where(assignable_type: "User")
      .where(assignable_id: user.id)
      .where(pending_cancellation_date: nil)
    return false if direct_org_seat_assignments.any?

    # This call will also be cheap, since a user can only have 0 or 1 direct assignments.
    direct_assignment_for_user = Copilot::SeatAssignment
      .where(owner: this_business)
      .where(assignable_type: "User")
      .where(assignable_id: user.id)
      .where(pending_cancellation_date: nil)
    return false if direct_assignment_for_user.any?

    return false if other_org_assignments.any? { |assignment| assignment.includes_user?(user) }
    return false if all_business_team_assignments.any? { |assignment| assignment.includes_user?(user) }

    true
  end

  sig { returns(T::Array[Copilot::SeatAssignment]) }
  memoize def other_org_assignments
    Copilot::SeatAssignment
      .where(organization_id: this_business.organization_ids)
      .where(assignable_type: %w[Team Organization])
      .where(pending_cancellation_date: nil).to_a
  end

  sig { returns(T::Array[Copilot::SeatAssignment]) }
  memoize def all_business_team_assignments
    Copilot::SeatAssignment.business_team_assignments(this_business)
      .where(pending_cancellation_date: nil).to_a
  end
end
