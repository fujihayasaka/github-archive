# typed: true
# frozen_string_literal: true

# This job will remove all repo keys created by a given OauthApplication in
# repositories for which the given User or Organization sets the access
# policy.
class RemoveRepoKeysForPolicymakerAndAppJob < ApplicationJob
  extend Scientist

  queue_as :remove_repo_keys_for_policymaker_and_app

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  REPOSITORY_BATCH_SIZE = 100

  # Public: Remove all public keys in repositories for which the given User
  # or Organization sets the access policy.
  #
  # policymaker_id - Integer ID for User or Organization policymaker
  # app_id         - Integer ID for the OauthApplication
  def perform(policymaker_id, app_id)
    policymaker = User.find_by(id: policymaker_id)
    oauth_app   = OauthApplication.find_by(id: app_id)

    return unless policymaker && oauth_app

    public_keys_to_destroy = T.let([], T::Array[T.nilable(::PublicKey)])
    PublicKey.repository_ids_for_policymaker(policymaker).each_slice(REPOSITORY_BATCH_SIZE) do |repo_ids|
      public_keys_to_destroy.concat(PublicKey.where(repository_id: repo_ids, oauth_application_id: oauth_app.id).to_a)
    end

    keys_count = public_keys_to_destroy.count

    # do not send instrumentation notification if nothing to destroy
    return if keys_count < 1

    public_keys_to_destroy.each { |key| with_write { T.must(key).destroy } }

    policymaker.instrument :revoke_repo_keys_for_policymaker_and_app,
      application_id: app_id,
      application_name: oauth_app.try(:name),
      keys_revoked: keys_count
  end
end
