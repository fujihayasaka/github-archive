# typed: true
# frozen_string_literal: true

class Stafftools::CopilotSeatsController < StafftoolsController
  extend T::Sig
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
      user_ids = Copilot::Seat.for_organization(this_user).pluck(:assigned_user_id)
      query = params[:query] || ""

      if query.present?
        user_ids = ::User.where(id: user_ids).where("login LIKE ?", "%#{query}%").pluck(:id)
      end

      copilot_seats = Copilot::Seat
                        .for_organization(this_user)
                        .where(assigned_user_id: user_ids)
                        .paginate(page: (params[:page] || 1), per_page: 20)

      render "stafftools/copilot_seats/show", locals: {
        copilot_organization: Copilot::Organization.new(this_user),
        copilot_seats: copilot_seats,
      }
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user.display_login))
    end
  end

  def update
    # possible values here are "organization" and "remove"
    seat_id          = params[:seat_id]
    organization_id  = params[:organization_id]
    assigned_user_id = params[:assigned_user_id]
    cancellation_at  = params[:cancellation_at]

    # we will just 404 on this
    seat         = Copilot::Seat.find(seat_id)
    organization = seat.organization

    # this is probably a dumb check but here we are.
    if seat.organization.id == organization_id.to_i && seat.assigned_user.id == assigned_user_id.to_i
      case cancellation_at
      when "organization"
        # this means that they want to schedule the seat to be canceled at the end of the billing cycle
        flash[:notice] = "Seat canceled"
        seat.staff_cancel_pending!(current_user)

        GitHub.logger.info(
          "Staff canceled seat",
          "gh.copilot.seat.id" => seat.id,
          "gh.organization.id" => organization_id,
          "gh.staff.user.id" => current_user.id,
        )
      when "remove"
        # this means that they want to remove the scheduled cancellation
        flash[:notice] = "Seat cancellation removed"
        seat.staff_uncancel_pending!(current_user)

        GitHub.logger.info(
          "Staff removed pending cancellation for seat",
          "gh.copilot.seat.id" => seat.id,
          "gh.organization.id" => organization.id,
          "gh.staff.user.id" => current_user.id,
        )
      else
        flash[:error] = "Invalid cancellation date"
      end
    else
      flash[:error] = "Seat not found"
    end

    redirect_to stafftools_user_copilot_seats_path(organization.display_login)
  end

  def destroy
    seat_id = params[:seat_id]
    organization_id = params[:organization_id]
    organization = Organization.find(organization_id)
    assigned_user_id = params[:assigned_user_id]

    seat = Copilot::Seat.find(seat_id)

    if !seat.present?
      flash[:error] = "Seat not found"
      redirect_to stafftools_user_copilot_seats_path(organization.display_login) and return
    end

    if seat.organization.id == organization_id.to_i && seat.assigned_user.id == assigned_user_id.to_i
      seat.cancel!(actor: current_user, staff_cancel: true)
      GitHub.logger.info(
        "Staff canceled seat immediately",
        "gh.copilot.seat.id" => seat.id,
        "gh.organization.id" => organization.id,
        "gh.staff.user.id" => current_user.id,
      )

      flash[:notice] = "Seat canceled"
    else
      flash[:error] = "Seat not found"
    end

    redirect_to stafftools_user_copilot_seats_path(organization.display_login)
  end
end
