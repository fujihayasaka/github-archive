# typed: strict
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotEnterpriseSeatAssignmentsController < Stafftools::Businesses::BusinessBaseController
      include GitHub::Memoizer

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

      sig { void }
      def show
        copilot_seat_assignments = ::Copilot::SeatAssignment.where(owner_id: this_business.id, owner_type: "Business")

        if params[:query].present?
          copilot_seat_assignments = filter_assignments_by_query(copilot_seat_assignments, params[:query])
        end

        copilot_seat_assignments = copilot_seat_assignments
          .to_a
          .paginate(page: (params[:page] || 1), per_page: 20)

        render "stafftools/businesses/copilot/enterprise_seat_assignments", locals: {
          copilot_business: ::Copilot::Business.new(this_business),
          copilot_seat_assignments: copilot_seat_assignments,
        }
      end

      sig { void }
      def update
        if seat_assignment.nil?
          flash[:error] = "Seat assignment not found"
          redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
        end

        assignment = T.must_because(seat_assignment) { "nil already handled" }

        is_cancelled = !assignment.pending_cancellation_date.nil?

        if is_cancelled
          flash[:error] = "Seat assignment is already pending cancellation"
          redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
        end

        if params[:operation] == "cancel"
          handle_cancel(assignment)
        elsif params[:operation] == "resync"
          handle_resync(assignment)
        end

        redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business)
      end

      sig { void }
      def destroy
        if seat_assignment.nil?
          flash[:error] = "Seat assignment not found"
          redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
        end

        assignment = T.must(seat_assignment)
        team_assignment = if assignment.assignable_type == "EnterpriseTeam"
          EnterpriseTeamAssignment.find_by(enterprise_team_id: assignment.assignable_id, assignment_type: "copilot")
        else
          nil
        end

        assignment.force_destroy!
        team_assignment.destroy unless team_assignment.nil?

        log_seat_assignment_details("Staff canceled seat assignment immediately")

        flash[:notice] = "Seat assignment cancelled"

        redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business)
      end

      private

      sig { returns(::Copilot::Business) }
      memoize def copilot_business
        ::Copilot::Business.new(this_business)
      end

      sig { returns(T.nilable(::Copilot::SeatAssignment)) }
      memoize def seat_assignment
        ::Copilot::SeatAssignment.find_by(
          id: params[:seat_assignment_id],
          owner_id: this_business.id,
          owner_type: "Business",
        )
      end

      sig { params(assignment: ::Copilot::SeatAssignment).void }
      def handle_cancel(assignment)
        result = GitHub::Result.new do
          if assignment.assignable_type == "EnterpriseTeam"
            team_assignment = EnterpriseTeamAssignment.find_by(enterprise_team_id: assignment.assignable_id, assignment_type: "copilot")
            # Destroying the associated EnterpriseTeamAssignment triggers an event that will cancel the assignment
            # See copilot_for_business_watched_events
            T.must(team_assignment).destroy
          else
            assignment.destroy!
          end
        end

        if result.ok?
          flash[:notice] = "Seat assignment cancelled"
        else
          flash[:error] = "Unable to update seat assignment"
        end

        log_seat_assignment_details(
          result.ok? ? "Staff seat assignment update succeeded" : "Staff seat assignment update failed"
        )
      end

      sig { params(assignment: ::Copilot::SeatAssignment).void }
      def handle_resync(assignment)
        job = ::Copilot::SeatManagement::SeatAssignmentConverterJob.perform_later(seat_assignment_id: assignment.id)

        job_id = if job.respond_to?(:job_id)
          T.cast(job, ::Copilot::SeatManagement::SeatAssignmentConverterJob).job_id
        else
          "unknown"
        end

        log_seat_assignment_details("Staff resynced seat assignment", "job_id" => job_id)

        flash[:notice] = "Seat assignment resyncing"
      end

      sig { params(msg: String, context: T::Hash[String, T.any(String, Integer)]).void }
      def log_seat_assignment_details(msg, context = {})
        GitHub.logger.info(msg, context.merge(
          "gh.copilot.seat_assignment.id" => seat_assignment&.id,
          "gh.copilot.seat_assignment.assignable_type" => seat_assignment&.assignable_type,
          "gh.copilot.seat_assignment.assignable_id" => seat_assignment&.assignable_id,
          "gh.copilot.seat_assignment.owner.id" => this_business.id,
          "gh.copilot.seat_assignment.owner_type" => seat_assignment&.owner_type,
          "gh.business.id" => this_business.id,
          "gh.staff.user.id" => current_user.id,
        ))
      end

      sig { params(assignments: ActiveRecord::Relation, query: String).returns(T::Array[::Copilot::SeatAssignment]) }
      def filter_assignments_by_query(assignments, query)
        assignments.select do |assignment|
          assignable = assignment.assignable
          case assignment.assignable_type
          when "EnterpriseTeam"
            team = T.cast(assignable, ::EnterpriseTeam)
            team.name.include?(query)
          when "User", "Organization"
            assignable.login.include?(query) || assignable.name.to_s.include?(query)
          else
            false
          end
        end
      end
    end
  end
end
