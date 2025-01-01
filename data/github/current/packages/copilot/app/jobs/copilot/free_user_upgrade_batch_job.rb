# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUserUpgradeBatchJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    sig { params(start: Integer, finish: Integer).void }
    def perform(start, finish)
      return unless FeatureFlag.vexi.enabled?(:free_user_upgrade_job, default: false) || noop?
      GitHub.logger.info("Starting FreeUserUpgradeBatchJob")
      Copilot::LimitedUser.find_each(start: start, finish: finish) do |limited_user|
        copilot_user = Copilot::User.new(T.must(limited_user.user))
        free_user = copilot_user.free_user
        next if free_user.nil? || !copilot_user.can_signup_for_free?

        named_tags = {
          "gh.user.id" => copilot_user.id,
          "gh.copilot.access_type" =>  copilot_user.access_type,
          "gh.copilot.free_user_type" =>  free_user.free_user_type,
          "gh.copilot.free_signup_reason" =>  copilot_user.free_signup_reason,
        }

        GitHub.logger.with_named_tags(named_tags) do
          GitHub.logger.info("Upgrading Copilot Free user to Copilot Complimentary Pro because they are eligible")
          with_write do
            subscribed = free_user.subscribe
            if subscribed
              limited_user.destroy
            else
              GitHub.logger.error("Failed to subscribe Copilot Free user to Copilot Complimentary Pro")
            end
          end unless noop?
        end
      end
    end

    sig { returns(T::Boolean) }
    def noop?
      FeatureFlag.vexi.enabled?(:free_user_upgrade_job_noop, default: false)
    end
  end
end
