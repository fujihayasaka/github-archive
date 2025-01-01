# typed: strict
# frozen_string_literal: true

class Businesses::CopilotLicensingUserAssignmentController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_is_not_trial
  before_action :ensure_enterprise_copilot_licensing_enabled
  before_action :ensure_can_assign_copilot_to_business_users

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  allow_verified_fetch only: [:create, :destroy]

  sig { void }
  def index
    seat_assignments = Copilot::SeatAssignment.where(owner_id: this_business.id, pending_cancellation_date: nil)
    seat_assignments_by_user_id = seat_assignments.index_by(&:assignable_id)

    # Get the search query from params
    query = params[:query].presence
    members = this_business.filtered_members(
      current_user,
      business_user_accounts_query: true,
      include_unaffiliated: true,
      query: query  # Pass the search query to the filtered_members method
    )

    users_without_copilot_access = []

    members.each do |member|
      user_object = member.is_a?(BusinessUserAccount) ? member.user : member
      next unless user_object.present?
      next if seat_assignments_by_user_id[user_object.id].present?

      user = {
        login: user_object.display_login,
        name: user_object.safe_profile_name,
        id: user_object.id,
        userUrl: user_path(user_object),
        avatarUrl: user_object.primary_avatar_url,
      }

      users_without_copilot_access << user
    end

    render json: {
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
  def check_business_is_not_trial
    render_404 if this_business.trial?
  end

  sig { void }
  def ensure_enterprise_copilot_licensing_enabled
    render_404 unless this_business.feature_enabled?(:enterprise_copilot_licensing)
  end

  sig { void }
  def ensure_can_assign_copilot_to_business_users
    render_404 unless this_business.can_assign_copilot_to_business_users?
  end
end
