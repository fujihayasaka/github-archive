# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotSeatAssignmentsController < StafftoolsController
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

  sig { void }
  def show
    if this_user.organization?
      copilot_seat_assignments = Copilot::SeatAssignment.for_owner(this_user)

      if params[:query].present?
        assignments_by_type = copilot_seat_assignments
        .pluck(:assignable_id, :assignable_type)
        .inject({}) do |acc, (id, type)|
          acc[type] ||= []
          acc[type] << id
          acc
        end

        query = params[:query]
        user_ids_to_search = (assignments_by_type["User"] || []) + (assignments_by_type["Organization"] || []) || []
        user_ids = ::User.where(id: user_ids_to_search).where("login LIKE ?", "%#{query}%").pluck(:id) || []
        team_ids = ::Team.where(id: assignments_by_type["Team"]).where("name LIKE ?", "%#{query}%").pluck(:id) || []
        organization_invite_ids = ::OrganizationInvitation
          .left_joins(:invitee)
          .where(id: assignments_by_type["OrganizationInvitation"])
          .where("users.login LIKE :query OR (organization_invitations.invitee_id IS NULL AND organization_invitations.email LIKE :query)", query: "%#{query}%")
          .pluck(:id) || []

        copilot_seat_assignments = Copilot::SeatAssignment
          .for_organization(this_user)
          .where(assignable_id: user_ids + team_ids + organization_invite_ids)
      end

      copilot_seat_assignments = copilot_seat_assignments.paginate(page: (params[:page] || 1), per_page: 20)

      render "stafftools/copilot_seat_assignments/show", locals: {
        copilot_organization: Copilot::Organization.new(this_user),
        copilot_seat_assignments: copilot_seat_assignments,
      }
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user))
    end
  end

  sig { void }
  def destroy
    seat_assignment_id = params[:seat_assignment_id]
    organization_id = params[:organization_id]
    organization = Organization.find_by(id: organization_id)

    seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

    if seat_assignment.nil? || organization.nil?
      flash[:error] = "Seat assignment not found"
      redirect_to stafftools_user_copilot_seat_assignments_path(organization) and return
    end

    seat_assignment = T.must(seat_assignment)
    organization = T.must(organization)
    if seat_assignment.organization_id == organization.id
      Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_later(seat_assignment.id, staff_actor: current_user)
      GitHub.logger.info(
        "Staff canceled seat assignment immediately",
        "gh.copilot.seat_assignment.id" => seat_assignment.id,
        "gh.organization.id" => organization.id,
        "gh.staff.user.id" => current_user.id,
      )

      flash[:notice] = "Seat assignment canceled"
    else
      flash[:error] = "Seat assignment not found"
    end

    redirect_to stafftools_user_copilot_seat_assignments_path(organization)
  end

  sig { void }
  def update
    seat_assignment_id = params[:seat_assignment_id]
    organization_id = params[:organization_id]
    organization = Organization.find_by(id: organization_id)

    if params[:job] == "reinstate_all"
      reinstate_all_seat_assignments(T.must(organization))
      return
    end

    seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

    if seat_assignment.nil? || organization.nil?
      flash[:error] = "Seat assignment not found"
      redirect_to stafftools_user_copilot_seat_assignments_path(organization) and return
    end

    seat_assignment = T.must(seat_assignment)
    organization = T.must(organization)

    if seat_assignment.owner_type == "Organization" && seat_assignment.owner_id == organization.id
      if params[:job] == "reinstate_user"
        job = Copilot::SeatManagement::ForceReinstateAccessJob.perform_later(seat_assignment_id: seat_assignment.id)
        job_id = job.respond_to?(:job_id) ? T.cast(job, Copilot::SeatManagement::ForceReinstateAccessJob).job_id : "unknown"
        GitHub.logger.info(
          "Staff reinstated access for seat assignment",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.organization.id" => organization.id,
          "gh.staff.user.id" => current_user.id,
          "gh.job.id" => job_id,
        )
        flash[:notice] = "Seat assignment access reinstated"
      elsif params[:job] == "resync"
        job = Copilot::SeatManagement::SeatAssignmentConverterJob.perform_later(seat_assignment_id: seat_assignment.id)

        job_id = job.respond_to?(:job_id) ? T.cast(job, Copilot::SeatManagement::SeatAssignmentConverterJob).job_id : "unknown"

        GitHub.logger.info(
          "Staff resynced seat assignment",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.organization.id" => organization.id,
          "gh.staff.user.id" => current_user.id,
          "gh.job.id" => job_id,
        )

        flash[:notice] = "Seat assignment resyncing"
      end
    else
      flash[:error] = "Seat assignment not found"
    end

    redirect_to stafftools_user_copilot_seat_assignments_path(organization)
  end

  private

  sig { params(organization: ::Organization).void }
  def reinstate_all_seat_assignments(organization)
    job = Copilot::SeatManagement::ForceReinstateAccessJob.perform_later(organization_id: organization.id)
    job_id = job.respond_to?(:job_id) ? T.cast(job, Copilot::SeatManagement::ForceReinstateAccessJob).job_id : "unknown"
    GitHub.logger.info(
      "Staff reinstated access for all seat assignments in the organization",
      "gh.organization.id" => organization.id,
      "gh.staff.user.id" => current_user.id,
      "gh.job.id" => job_id,
    )
    flash[:notice] = "Seat assignment access reinstated"
    redirect_to stafftools_user_copilot_seat_assignments_path(organization) and return
  end
end
