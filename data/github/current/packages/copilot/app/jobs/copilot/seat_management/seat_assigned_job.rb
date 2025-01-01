# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class SeatAssignedJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job

      resolve_tenant_context do |organization_id|
        ::Organization.find_by(id: organization_id)&.business
      end

      # Sends an email to the user that they have been assigned a Copilot seat by
      # their organization. If the user has a Copilot Individual subscription,
      # they will receive a prorated refund.
      #
      # This takes the organization ID and user ID as arguments because it is
      # called from other batch jobs that do not have the Organization or User
      # objects loaded.
      sig { params(organization_id: Integer, user_id: Integer, seat: T.nilable(Copilot::Seat)).void }
      def perform(organization_id, user_id, seat: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => organization_id,
          "gh.user.id" => user_id,
        ) do
          chatterbox_say("Seat assigned to user #{user_id} in organization #{organization_id}")
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @user_id         = T.let(user_id, T.nilable(Integer))

          GitHub.logger.info("Loading organization and user")

          organization     = ::Organization.find_by(id: T.must(@organization_id))
          return report_error("Invalid Organization") unless organization

          copilot_organization = Copilot::Organization.new(organization)
          return GitHub.logger.error("Organization not enabled for CFB") unless copilot_organization.copilot_for_business_enabled?

          user = ::User.find_by(id: @user_id)
          return report_error("Invalid User") unless user

          # let's triple check that the Seat still exists
          seat = Copilot::Seat.find_by(organization: organization, assigned_user: user)
          return report_error("Missing Seat") unless seat

          with_write do
            # Run the normal callbacks for creation of the seat.
            seat.run_callbacks(:create)
          end

          MemberFeatureRequest::CopilotForBusinessSeatStatusJob.perform_later(
            organization_id: organization.id,
            user_id: user.id
          )

          copilot_user = Copilot::User.new(user)
          GitHub.logger.info("Sending email to user for newly assigned seat",
                             "gh.copilot.seat.id" => seat.id)

          # We want to avoid deleting existing subscriptions if the org is on a trial,
          # to prevent users getting their CfI access removed unnecessarily. When the trial
          # is converted to a paid subscription we'll go through and remove the FreeUser records
          # and CfI subscriptions via the Copilot::BusinessTrials::UpgradeCleanupJob
          if copilot_organization.business_trial&.active?
            mailer_class = copilot_organization.business_trial&.mailer_class

            return unless mailer_class

            mailer_class
            .trial_seat_added_for_user(organization, user, T.must(copilot_organization.business_trial).trial_length)
            .deliver_later
          else
            # Check for a Copilot free user subscription. If the user has one, we
            # will delete it.
            GitHub.logger.info("Deleting any FreeUser records", "gh.copilot.seat.id" => seat.id)
            with_write do
              Copilot::FreeUser.where(user_id: user_id).destroy_all
            end

            # Check for a Copilot Individual subscription. The user will
            # receive a prorated refund if one exists.
            result = copilot_user.cancel_and_refund_active_subscription(
              organization: organization,
            )
            refunding = result.value!
            if refunding
              GitHub.logger.info("Not sending email, user will receive an email from the refund job",
                                 "gh.copilot.seat.id" => seat.id)
              return
            end

            if copilot_organization.copilot_plan_enterprise?
              CopilotEnterpriseMailer.welcome_individual(organization, user).deliver_later
            else
              CopilotForBusinessMailer.seat_added_for_user(organization, user).deliver_later
            end
          end

          # Check for a Copilot limited user subscription. If the user has one, we will delete it.
          GitHub.logger.info("Deleting any LimitedUser records", "gh.copilot.seat.id" => seat.id)
          with_write do
            Copilot::LimitedUser.where(user_id: user_id).destroy_all
          end

          # update the cache you scallywag
          copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
          if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
            Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
          end
          chatterbox_say("Copilot seat assigned to #{user.display_login} in #{organization.display_login}")
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.organization.id" => @organization_id,
          "gh.user.id" => @user_id,
        }
        handle_copilot_error(Copilot::Errors::SeatCreationError.new(message), details)
      end
    end
  end
end
