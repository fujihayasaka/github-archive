# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseRemoveMemberJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_enterprise_remove_member_job

      resolve_tenant_context do |data|
        business = ::Business.find_by(id: data[:business_id])
        business
      end

      sig do
        params(
          user_id: Integer,
          business_id: Integer,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(user_id:, business_id:, transaction_id: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.actor.id" => actor_id,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.business.id" => business_id,
          "gh.user.id" => user_id,
        ) do
          @user_id = T.let(user_id, T.nilable(Integer))
          @business_id = T.let(business_id, T.nilable(Integer))
          @transaction_id = T.let(transaction_id, T.nilable(String))
          @payload = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id = T.let(actor_id, T.nilable(Integer))

          # load up the business - this is required so if it isn't there, report an exception
          business = ::Business.find_by(id: business_id)
          return report_error("User being removed from invalid or non-existent Business") unless business

          user = ::User.find_by(id: user_id)
          unless user
            # why? just why? what is happening? we don't have a user but the user was added to the business or restored or something?
            GitHub.logger.error("User being removed from business is invalid or non-existent")
            Copilot::SeatManagement::UserJob.perform_now(user_id: user_id, clean_records: true)
            return
          end

          # Find all businessteam OR user assignment associated Seats for this user
          # .business_owned only returns BusinessTeam and User assignments, not EnterpriseTeam assignments
          # EnterpriseTeam assignments will be handled in a separate job
          business_owned_assignments = Copilot::Seat.business_owned(business).where(assigned_user_id: user_id).map(&:seat_assignment)
          copilot_business = Copilot::Business.new(business)
          if business_owned_assignments.empty?
            GitHub.logger.info("No User or BusinessTeam Copilot seat assignments to remove for user being removed from business", "gh.copilot.copilot_enabled" => copilot_business.copilot_enabled?)
            return
          end

          actor = actor_id ? ::User.find_by(id: actor_id) : nil

          # Handle business team assignments - create disassociated seat assignments
          business_owned_assignments.each do |assignment|
            case assignment&.assignable_type
            when "User"
              GitHub.logger.info(
                  "Revoking access to User SeatAssignment for member removed from business",
                  "gh.copilot.seat_assignment.id" => assignment&.id,
                )
              with_write do
                assignment&.unassign_and_revoke_access!(actor, :business_member_removed)
              end
            when "BusinessTeam"
              # we should only ever find one seat for the user for a business team
              assignment&.seats&.where(assigned_user_id: user_id)&.each do |seat|
                GitHub.logger.info(
                  "Creating disassociated SeatAssignment for BusinessTeam member removed from business",
                  "gh.copilot.seat_assignment.id" => assignment&.id,
                  "gh.copilot.seat.id" => seat.id,
                )

                with_write do
                  user_assignment = create_disassociated_seat_assignment(
                    user_id,
                    seat,
                    T.must(assignment),
                    :business_member_removed,
                    actor,
                  )
                  seat.update_column(:copilot_seat_assignment_id, user_assignment.id)
                  user_assignment.unassign_and_revoke_access!(actor, :business_member_removed)
                end
              end
            end
          end

          # update cache and emit billable customer change now that the user is no longer in the business
          copilot_user = Copilot::User.new(user)
          copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

          if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
            Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
          end
        end
      end

      private

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.business.id" => @business_id,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.user.id" => @user_id,
        }
        handle_copilot_error(Copilot::Errors::SeatDestructionError.new(message), details)
      end
    end
  end
end
