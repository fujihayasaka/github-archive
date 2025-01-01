# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SuspendEmuAndRemoveExternalIdentityJob < ApplicationJob
  queue_as :suspend_emu_and_remove_external_identity
  retry_on_dirty_exit

  def perform(user_id:, obfuscate_users: false, obfuscate_with_shortcode: true, actor_id: nil)
    unless user = User.find_by(id: user_id)
      GitHub.dogstats.increment("external_identities.suspend_emu_and_remove_external_identity_job.user_not_found")
      GitHub.logger.error({ "exception.message" => "User not found", "gh.user.id" => user_id })
      return
    end

    unless user.is_enterprise_managed?
      GitHub.dogstats.increment("external_identities.suspend_emu_and_remove_external_identity_job.not_emu")
      GitHub.logger.error({ "exception.message" => "User is not enterprise managed", "gh.user.id" => user_id })
      return
    end

    GitHub.logger.info({
      msg: "Starting job to suspend and remove external identity for EMU user",
      "gh.user.id": user.id,
      "gh.business.id": user.enterprise_managed_business&.id,
    })

    if user.external_identities.count > 1
      GitHub.logger.error({ "exception.message" => "EMU user has more than 1 external identity", "gh.user.id" => user_id, "gh.business.id" => user.enterprise_managed_business&.id })
      GitHub.dogstats.increment("external_identities.suspend_emu_and_remove_external_identity_job.many_ext_id")
    end

    ei = user.external_identities.first

    if obfuscate_users
      login_suffix = obfuscate_with_shortcode ? user.login_suffix : nil

      ei_id = ei&.id
      ei_external_id = ei&.external_id
      ei_user_name = ei&.user_name
      obfuscated_login = User.standardize_login(
        Platform::Provisioning::UserDataReconciler.obfuscate_value(ei_user_name || user.login, ei_external_id || "", login_suffix),
        suffix: login_suffix
      )
      with_write { user.update(login: obfuscated_login) }
      GitHub.logger.info({
        msg: "Obfuscated user",
        "gh.user.id": user_id,
        "gh.user.login": obfuscated_login,
        "gh.business.id": user.enterprise_managed_business&.id,
      })
    end

    cleanup_deploy_keys = GitHub.flipper[:external_identity_cleanup_deploy_keys].enabled?(user.enterprise_managed_business)
    with_write { ExternalIdentity.cleanup_user(user, deploy_keys: cleanup_deploy_keys) }

    actor = actor_id.present? ? User.find(actor_id) : nil

    suspended = suspend_user(user, actor)

    unless suspended
      GitHub.logger.error({ "exception.message" => "Failed to suspend EMU user", "gh.user.id" => user_id, "gh.business.id" => user.enterprise_managed_business&.id })
      GitHub.dogstats.increment("external_identities.suspend_emu_and_remove_external_identity_job.user_suspend_failed")
    end

    with_write { ei.disable } if ei

    GitHub.logger.info({
      msg: "Finished job to suspend and remove external identity for EMU user",
      "gh.user.id": user.id,
      "gh.business.id": user.enterprise_managed_business&.id,
    })
  end

  def suspend_user(user, actor)
    with_write { user.suspend("EMU obfuscation and suspension job run at #{Time.now.utc}", actor: actor) }
  end
end
