# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotStandaloneAssignmentsController < Stafftools::Businesses::BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        only: [:show]

      def show
        copilot_seat_assignments = ::Copilot::SeatAssignment
          .where(owner_id: this_business.id, assignable_type: "EnterpriseTeam")

        if params[:query].present?
          team_ids = copilot_seat_assignments.pluck(:assignable_id)
          eterprise_teams = EnterpriseTeam.where(id: team_ids).where("name LIKE :query", query: "%#{params[:query]}%")
          copilot_seat_assignments = ::Copilot::SeatAssignment
            .includes(:seats, assignable: { enterprise_team_group_mappings: :external_group })
            .where(owner_id: this_business.id, assignable_id: eterprise_teams.pluck(:id), assignable_type: "EnterpriseTeam")
        end

        copilot_seat_assignments = copilot_seat_assignments
          .to_a
          .filter { |sa| sa.assignable.present? }
          .sort_by { |assignment| assignment.assignable&.slug }
          .paginate(page: (params[:page] || 1), per_page: 20)

        render "stafftools/businesses/copilot/standalone_seat_assignments", locals: {
          copilot_business: ::Copilot::Business.new(this_business),
          copilot_seat_assignments: copilot_seat_assignments,
        }
      end

      def update
        seat_assignment = ::Copilot::SeatAssignment.find_by(
          owner_id: this_business.id,
          id: params[:seat_assignment_id],
          assignable_type: "EnterpriseTeam"
        )

        if seat_assignment.nil?
          flash[:error] = "Seat assignment not found"
          redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
        end

        seat_assignment = T.must(seat_assignment)
        is_cancelled = !seat_assignment.pending_cancellation_date.nil?

        if is_cancelled
          flash[:error] = "Seat assignment is already pending cancellation"
          redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
        end

        result = GitHub::Result.new do
          team_assignment = EnterpriseTeamAssignment.find_by(enterprise_team_id: seat_assignment.assignable_id, assignment_type: "copilot")
          T.must(team_assignment).destroy
        end

        if result.ok?
          flash[:notice] = "Seat assignment cancelled"
        else
          flash[:error] = "Unable to update seat assignment"
        end

        GitHub.logger.info(
          result.ok? ? "Staff seat assignment update succeeded" : "Staff seat assignment update failed",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.owner.id" => this_business.id,
          "gh.staff.user.id" => current_user.id,
        )

        redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business)
      end

      def destroy
        seat_assignment_id = params[:seat_assignment_id]
        business = this_business

        seat_assignment = ::Copilot::SeatAssignment.find_by(id: seat_assignment_id, owner_id: this_business.id)
        team_assignment = EnterpriseTeamAssignment.find_by(enterprise_team_id: seat_assignment&.assignable_id, assignment_type: "copilot")

        if seat_assignment.nil?
          flash[:error] = "Seat assignment not found"
          redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
        end

        seat_assignment = T.must(seat_assignment)
        seat_assignment.force_destroy!

        team_assignment.destroy unless team_assignment.nil?

        GitHub.logger.info(
          "Staff canceled seat assignment immediately",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.organization.id" => seat_assignment.organization_id,
          "gh.owner.id" => this_business.id,
          "gh.staff.user.id" => current_user.id,
        )

        flash[:notice] = "Seat assignment cancelled"

        redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business)
      end

      private

      memoize def copilot_business
        ::Copilot::Business.new(this_business)
      end
    end
  end
end
