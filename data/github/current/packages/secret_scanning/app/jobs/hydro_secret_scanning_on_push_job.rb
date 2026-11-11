# typed: true
# frozen_string_literal: true

class HydroSecretScanningOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_secret_scanning_on_push
  retry_on_dirty_exit
  retry_on GitRPC::ObjectMissing # in case we're too fast (this happens)

  sig { void }
  def perform
    updates = ref_updates.map do |update|
      Git::Ref::Update.new(repository: repository, refname: update.ref, before_oid: update.before, after_oid: update.after)
    end
    SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(repository, updates, pusher)
  end
end
