# typed: strict
# frozen_string_literal: true

# Note: Copilot::UpdateUserSettingsCacheJob is a different job that updates users for a given org
class Copilot::UserCacheCreateJob < CopilotJob
  queue_as :copilot_user_cache_create
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 1.minute, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  resolve_tenant_context do |args|
    ::User.find_by(id: args[:user_id])&.enterprise_managed_business
  end

  sig { params(user_id: Integer).void }
  def perform(user_id:)
    GitHub.logger.with_named_tags("gh.user.id" => user_id) do
      user = User.find_by(id: user_id)
      return unless user

      copilot_user = Copilot::User.new(user)
      copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION, throttle: true)
    end
  end
end
