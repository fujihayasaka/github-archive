# typed: true
# frozen_string_literal: true

class HydroSecretScanningOnPushJob < Repositories::PushHydroMessageJob
  extend T::Sig

  queue_as :hydro_secret_scanning_on_push

  sig { void }
  def perform
    updates = ref_updates.map do |update|
      Git::Ref::Update.new(repository: repository, refname: update.ref, before_oid: update.before, after_oid: update.after)
    end
    SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(repository, updates, pusher)
  end
end
