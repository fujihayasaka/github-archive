# typed: strict
# frozen_string_literal: true

class Businesses::CopilotLicensingUserAssignmentController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_enterprise_copilot_licensing_enabled
  before_action :ensure_can_assign_copilot_to_business_users

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  allow_verified_fetch only: [:create, :destroy]

  sig { void }
  def index
    # Get the search query from params
    query = params[:query].presence
    members = this_business.filtered_members(
      current_user,
      business_user_accounts_query: true,
      include_unaffiliated: true,
      query: query  # Pass the search query to the filtered_members method
    )

    query_with_access = params[:withAccess] == "true"

    # Get all Copilot seats directly assigned to users for this business, only these will be shown in the view.
    all_direct_business_seats = Copilot::Seat.business_owned(this_business).where(copilot_seat_assignments: { assignable_type: "User" })
    direct_business_seats_by_user = all_direct_business_seats.group_by(&:assigned_user_id)

    # Get all Copilot seats for these users. We need this to display all of their licenses in the view.
    # Instead of fetching all seats for all users, only fetch all seats for users with a direct business seat.
    seats_by_user = {}
    direct_business_seats_by_user.each_key do |user_id|
      user = User.find_by(id: user_id)
      next unless user
      seats_by_user[user_id] = Copilot::Seat.for_business_user_ids(this_business, user_id).to_a
    end

    users_with_copilot_access = []
    users_without_copilot_access = []

    members.each do |member|
      user_object = member.is_a?(BusinessUserAccount) ? member.user : member
      next unless user_object.present?

      # We're only going to be quering for either users that have access or don't have access. There's no point in populating both lists.
      user_has_access = direct_business_seats_by_user[user_object.id].present?
      next if query_with_access && !user_has_access
      next if !query_with_access && user_has_access

      user_url = user_path(user_object)
      avatar_url = user_object.primary_avatar_url
      user_seats = seats_by_user[user_object.id] || []
      plan_types = Copilot::Seat.seat_plan_types_by_owner_type(user_seats)
      licenses = get_all_copilot_license_info_from_user_seats(user_seats, plan_types, this_business)
      dominant_license = get_dominant_license_from_user_seats(user_seats, plan_types)

      user = {
        login: user_object.display_login,
        name: user_object.safe_profile_name,
        id: user_object.id,
        userUrl: user_url,
        avatarUrl: avatar_url,
        licenses: licenses,
        dominantLicense: dominant_license,
      }

      if user_has_access
        users_with_copilot_access << user
      else
        users_without_copilot_access << user
      end
    end

    render json: {
      withCopilotAccess: users_with_copilot_access,
      withoutCopilotAccess: users_without_copilot_access,
    }
  end

  sig { void }
  def create
    ids = params[:users].map(&:to_i)
    users = User.where(id: ids, type: "User").to_a
    result = copilot_business.assign(users, current_user)

    if result.ok?
      head :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    ids = params[:users].map(&:to_i)
    users = User.where(id: ids, type: "User").to_a
    result = copilot_business.unassign(users, current_user)

    if result.ok?
      head :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    ::Copilot::Business.new(this_business)
  end

  sig { void }
  def ensure_can_assign_copilot_to_business_users
    render_404 unless this_business.can_assign_copilot_to_business_users?
  end

  sig { params(seats: T::Array[Copilot::Seat], plan_types: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def get_dominant_license_from_user_seats(seats, plan_types)
    return {} if seats.nil?
    seats.sort_by! do |seat|
      [
        Copilot::Seat.priority_for_copilot_sku(seat.copilot_sku),
        seat.owner.is_a?(Organization) ? 0 : 1
      ]
    end

    dominant_license = seats.first
    return {} if dominant_license.nil?

    plan_type = plan_types.dig(dominant_license.seat_assignment&.id, :plan) # Get the plan type for the seat
    owner_type = dominant_license.owner.is_a?(Business) ? "business" : "organization"
    owner_name = dominant_license.owner.name
    owner_id = dominant_license.owner.id

    {
      ownerType: owner_type,
      ownerName: owner_name,
      ownerId: owner_id,
      expirationDate: dominant_license.pending_cancellation_date,
      planType: plan_type,
    }
  end

  sig { params(seats: T::Array[Copilot::Seat], plan_types: T::Hash[T.untyped, T.untyped], business: Business).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_all_copilot_license_info_from_user_seats(seats, plan_types, business)
    licenses = []
    seats.each do |seat|
      plan_type = plan_types.dig(seat.seat_assignment&.id, :plan) # Get the plan type for the seat
      owner_type = seat.owner.is_a?(Business) ? "business" : "organization"
      owner_name = seat.owner.name
      owner_id = seat.owner.id
      license = {
        ownerType: owner_type,
        ownerName: owner_name,
        ownerId: owner_id,
        expirationDate: seat.pending_cancellation_date,
        planType: plan_type,
      }
      licenses << license
    end

    licenses
  end
end
