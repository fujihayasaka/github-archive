# typed: true
# frozen_string_literal: true

class Stafftools::Users::EmuLoginObfuscationController < StafftoolsController
  before_action :ensure_enterprise_managed_user
  before_action :ensure_hard_deprovisioned

  # Obfuscate the user's login. This action:
  # - Generates an obfuscated login using a SHA256 hash.
  # - Renames the user to the obfuscated login.
  #
  # This is used when a user has been hard deprovisioned but their login was not obfuscated
  # due to a silent failure in the reconciler (e.g., user was already suspended, rename failed).
  def update
    external_identity = this_user.external_identities.first
    display_login = this_user.display_login

    suffix = this_user.login_suffix
    ei_user_name = external_identity&.user_name
    ei_external_id = external_identity&.external_id

    obfuscated_login = User.standardize_login(
      Platform::Provisioning::UserDataReconciler.obfuscate_value(
        ei_user_name || this_user.login, ei_external_id || "", suffix
      ),
      suffix: suffix
    )

    success = this_user.rename(obfuscated_login, actor: current_user, allow_rename: true)

    if success
      flash[:notice] = "User #{display_login} login has been obfuscated. New login: #{obfuscated_login}. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}"
    else
      GitHub.logger.error(
        "Error while obfuscating user login from stafftools",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.user.id" => this_user.id,
        "gh.user.login" => this_user.login,
        "gh.user.new_login" => obfuscated_login,
        "gh.business.id" => this_user.enterprise_managed_business&.id,
        "exception.message" => this_user.errors.full_messages.join(", "),
      )
      flash[:error] = "There was an error obfuscating login for user #{display_login}. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}. #{this_user.errors.full_messages.join(", ")}"
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  def ensure_hard_deprovisioned
    external_identity = this_user.external_identities.first
    unless external_identity&.deleted_at?
      head :not_found
    end
  end
end
