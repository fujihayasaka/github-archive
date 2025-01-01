# typed: true
# frozen_string_literal: true

class Stafftools::CopilotSeatsController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required
  before_action :ensure_user_exists, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    if this_user.organization?
      user_ids = Copilot::Seat.for_owner(this_user).pluck(:assigned_user_id)
      query = params[:query] || ""

      if query.present?
        user_ids = ::User.where(id: user_ids).where("login LIKE ?", "%#{query}%").pluck(:id)
      end

      copilot_seats = Copilot::Seat
                        .for_owner(this_user)
                        .where(assigned_user_id: user_ids)
                        .paginate(page: (params[:page] || 1), per_page: 20)

      render "stafftools/copilot_seats/show", locals: {
        copilot_organization: Copilot::Organization.new(this_user),
        copilot_seats: copilot_seats,
      }
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user))
    end
  end

  def update
    seat_id          = params[:seat_id]
    assigned_user_id = params[:assigned_user_id]
    cancellation_at  = params[:cancellation_at]
    owner_id         = params[:owner_id]

    seat         = Copilot::Seat.find(seat_id)
    owner        = seat.seat_assignment&.owner

    if !seat.assigned_user.present?
      flash[:error] = "Cannot remove pending cancellation for seat with missing user."
    elsif owner.nil?
      flash[:error] = "Seat assignment or owner not found"
    elsif owner&.id == owner_id.to_i && seat.assigned_user&.id == assigned_user_id.to_i
      case cancellation_at
      when "owner"
        # this means that they want to schedule the seat to be canceled at the end of the billing cycle
        flash[:notice] = "Seat scheduled for cancellation"
        seat.staff_set_pending_cancellation!(current_user)

        GitHub.logger.info(
          "Staff canceled seat via Stafftools",
          "gh.copilot.seat.id" => seat.id,
          "gh.owner.id" => owner_id,
          "gh.owner_type" => owner.class.name,
          "gh.staff.user.id" => current_user.id,
        )
      when "remove"
        # this means that they want to remove the scheduled cancellation
        flash[:notice] = "Seat cancellation removed"
        seat.staff_remove_pending_cancellation!(current_user)

        GitHub.logger.info(
          "Staff removed pending cancellation date for seat",
          "gh.copilot.seat.id" => seat.id,
          "gh.owner.id" => owner_id,
          "gh.owner_type" => owner.class.name,
          "gh.staff.user.id" => current_user.id,
        )
      else
        flash[:error] = "Invalid cancellation date"
      end
    else
      flash[:error] = "Seat not found"
    end

    if owner.is_a?(::Organization)
      redirect_to stafftools_user_copilot_seats_path(owner)
    else
      redirect_to standalone_seats_stafftools_copilot_path(owner)
    end
  end

  def destroy
    seat_id = params[:seat_id]
    assigned_user_id = params[:assigned_user_id]
    owner_id         = params[:owner_id]

    # we will just 404 on this
    seat         = Copilot::Seat.find(seat_id)
    owner        = seat.seat_assignment&.owner

    if !seat.present?
      flash[:error] = "Seat not found"
      if owner.is_a?(::Organization)
        redirect_to stafftools_user_copilot_seats_path(owner) and return
      else
        redirect_to standalone_seats_stafftools_copilot_path(owner) and return
      end
    end

    if owner&.id == owner_id.to_i && seat.assigned_user_id == assigned_user_id.to_i
      seat.cancel!(actor: current_user, staff_cancel: true)
      GitHub.logger.info(
        "Staff canceled seat immediately",
        "gh.copilot.seat.id" => seat.id,
        "gh.owner.id" => owner_id,
        "gh.owner_type" => owner.class.name,
        "gh.staff.user.id" => current_user.id,
      )

      flash[:notice] = "Seat canceled"
    else
      flash[:error] = "Seat not found"
    end

    if owner.is_a?(::Organization)
      redirect_to stafftools_user_copilot_seats_path(owner)
    else
      redirect_to standalone_seats_stafftools_copilot_path(owner)
    end
  end
end
