# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUserCouponCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    extend T::Sig

    locked_by timeout: 20.minutes, key: DEFAULT_LOCK_PROC
    schedule interval: 24.hours, condition: -> { GitHub.copilot_for_individuals_enabled? }
    gate_with_feature_flag :copilot_free_user_coupon_check_job

    sig { params(free_user_id: T.nilable(Integer)).void }
    def perform(free_user_id: nil)
      GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.free_user.id" => free_user_id) do
        # if we get a free user id passed, we're gonna check if the coupon is still active
        GitHub.logger.info("Starting FreeUserCouponCheckJob")
        if free_user_id.present?
          free_user = Copilot::FreeUser.find_by(id: free_user_id)
          return handle_copilot_error(Copilot::Errors::FreeUserError.new("No free user found")) unless free_user.present?
          return handle_copilot_error(Copilot::Errors::FreeUserError.new("No user found")) unless free_user.user.present?

          # we're not going to send this to sentry, just log it
          unless [Copilot::FreeUser::EDUCATIONAL.name, Copilot::FreeUser::FACULTY.name, Copilot::FreeUser::WORKSHOP.name].include?(free_user.free_user_type)
            GitHub.logger.error("Expected Educational/Faculty/Workshop Free User Type", "gh.copilot.free_user.free_user_type" => free_user.free_user_type)
            return
          end

          GitHub.logger.info("Checking coupon state for free user")

          copilot_user = Copilot::User.new(T.must(free_user.user))

          if Copilot::FreeUser.is_educational_user?(copilot_user) || Copilot::FreeUser.is_faculty_user?(copilot_user) || Copilot::FreeUser.is_workshop_user?(copilot_user)
            GitHub.logger.info("Free user still has valid coupon")
            return
          else
            GitHub.logger.info("Free user no longer has valid coupon, destroying")
            with_write do
              free_user.destroy!
            end
          end
        else
          check_educational
          check_workshop
        end
      end
    end

    sig { void }
    def check_educational
      educational_users = with_read do
        Copilot::FreeUser.educational + Copilot::FreeUser.faculty
      end

      GitHub.logger.info("Loaded educational users", "gh.copilot.free_user.educational.count" => educational_users.count)

      if educational_users.any?
        GitHub.logger.info("Checking coupons for educational users", "gh.copilot.free_user.educational.count" => educational_users.count)
        educational_users.each do |free_user|
          Copilot::FreeUserCouponCheckJob.perform_later(free_user_id: free_user.id)
        end
      end
    end

    sig { void }
    def check_workshop
      workshop_users = with_read do
        Copilot::FreeUser.workshop
      end

      GitHub.logger.info("Loaded workshop coupon users", "gh.copilot.free_user.workshop.count" => workshop_users.count)

      if workshop_users.any?
        GitHub.logger.info("Checking coupons for workshop users", "gh.copilot.free_user.workshop.count" => workshop_users.count)
        workshop_users.each do |free_user|
          Copilot::FreeUserCouponCheckJob.perform_later(free_user_id: free_user.id)
        end
      end
    end
  end
end
