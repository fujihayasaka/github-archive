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
        ApplicationRecord::Accounts,
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

        if params[:job] == "reinstate_user"
          handle_reinstate(assignment)
        elsif params[:operation] == "cancel"
          is_cancelled = !assignment.pending_cancellation_date.nil?
          if is_cancelled
            flash[:error] = "Seat assignment is already pending cancellation"
            redirect_to standalone_seat_assignments_stafftools_copilot_path(this_business) and return
          end
          handle_cancel(assignment)
        elsif params[:operation] == "resync"
          handle_resync(assignment)
        elsif params[:operation] == "uncancel"
          handle_uncancel(assignment)
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

        assignment.force_destroy!(actor: current_user)

        log_seat_assignment_details("Staff canceled seat assignment immediately")

        flash[:notice] = "Seat assignment cancelled immediately"

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
          assignment.set_pending_cancellation_date_to_before_next_billing_cycle
        end

        if result.ok?
          flash[:notice] = "Seat assignment scheduled for cancellation"
        else
          flash[:error] = "Unable to schedule seat assignment for cancellation"
        end

        log_seat_assignment_details(
          result.ok? ? "Staff scheduled seat assignment for cancellation" : "Staff seat assignment schedule failed"
        )
      end

      sig { params(assignment: ::Copilot::SeatAssignment).void }
      def handle_reinstate(assignment)
        job = ::Copilot::SeatManagement::ForceReinstateAccessJob.perform_later(seat_assignment_id: assignment.id)
        job_id = if job.respond_to?(:job_id)
          T.cast(job, ::Copilot::SeatManagement::ForceReinstateAccessJob).job_id
        else
          "unknown"
        end
        log_seat_assignment_details("Staff reinstated access for seat assignment", "job_id" => job_id)

        if params[:also_uncancel] == "1" && assignment.pending_cancellation?
          ::Copilot::SeatManagement::UncancelSeatAssignmentJob.perform_later(seat_assignment_id: assignment.id)
          log_seat_assignment_details("Staff also removed pending cancellation during reinstatement")
          flash[:notice] = "Seat assignment access reinstated and pending cancellation removed"
        else
          flash[:notice] = "Seat assignment access reinstated"
        end
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

      sig { params(assignment: ::Copilot::SeatAssignment).void }
      def handle_uncancel(assignment)
        job = ::Copilot::SeatManagement::UncancelSeatAssignmentJob.perform_later(seat_assignment_id: assignment.id)
        job_id = if job.respond_to?(:job_id)
          T.cast(job, ::Copilot::SeatManagement::UncancelSeatAssignmentJob).job_id
        else
          "unknown"
        end
        log_seat_assignment_details("Staff uncanceled seat assignment", "job_id" => job_id)
        flash[:notice] = "Seat assignment uncanceling"
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
