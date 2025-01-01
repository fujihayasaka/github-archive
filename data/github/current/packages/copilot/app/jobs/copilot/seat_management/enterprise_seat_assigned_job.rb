# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseSeatAssignedJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job

      # This just runs the callbacks for the Seat.
      #
      # This takes the owner ID and user ID as arguments because it is
      # called from other batch jobs that do not have the Owner or User
      # objects loaded.
      sig { params(owner_id: Integer, user_id: Integer, seat: T.nilable(Copilot::Seat)).void }
      def perform(owner_id, user_id, seat: nil)
        # set these for error reporting
        @owner_id = T.let(owner_id, T.nilable(Integer))
        @user_id  = T.let(user_id, T.nilable(Integer))

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.business.id" => owner_id,
          "gh.user.id" => user_id,
        ) do
          chatterbox_say("Seat assigned to user #{user_id} in business #{owner_id}")

          GitHub.logger.info("Loading business and user")

          business = ::Business.find_by(id: owner_id)
          return report_error("Invalid Business") unless business

          user = ::User.find_by(id: user_id)
          return report_error("Invalid User") unless user

          # let's triple check that the Seat still exists
          user_seats = Copilot::Seat.for_assigned_user_and_owner(user, business)
          return report_error("Missing Seat") unless user_seats.any?

          with_write do
            # Run the normal callbacks for creation of the seat.
            user_seats.each do |seat|
              seat.run_callbacks(:create)
            end
          end

          GitHub.logger.info("Sending email to user")
          CopilotForBusinessMailer.seat_added_for_user(business, user).deliver_later
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.copilot.seat_assignment.owner.id" => @owner_id,
          "gh.user.id" => @user_id,
        }
        handle_copilot_error(Copilot::Errors::SeatCreationError.new(message), details)
      end
    end
  end
end
