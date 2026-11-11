# typed: true
# frozen_string_literal: true

class Stafftools::Users::EmuLoginObfuscationController < StafftoolsController
  before_action :ensure_enterprise_managed_user

  # Obfuscate the user's login, profile name, and profile email. This action:
  # - Generates an obfuscated login using a SHA256 hash.
  # - Renames the user to the obfuscated login.
  # - Sets the profile name to an empty string.
  # - Obfuscates the profile email using the obfuscated login.
  #
  # Each operation runs independently so partial failures from a previous
  # deprovisioning attempt can be cleaned up regardless of which
  # steps originally succeeded or failed.
  def update
    if  fix_emu_deprovisioning_errors_enabled? && this_user.renaming?
      this_user.update_attribute(:renaming, nil)
    end

    external_identity = this_user.external_identities.first
    display_login = this_user.display_login

    suffix = this_user.login_suffix
    ei_user_name = external_identity&.user_name
    ei_external_id = external_identity&.external_id

    already_obfuscated = login_already_obfuscated?(this_user, suffix)

    errors = []
    exceptions = []

    if already_obfuscated
      obfuscated_login = this_user.login
    else
      obfuscated_login = User.standardize_login(
        Platform::Provisioning::UserDataReconciler.obfuscate_value(
          ei_user_name || this_user.login, ei_external_id || "", suffix
        ),
        suffix: suffix
      )

      unless this_user.rename(obfuscated_login, actor: current_user, allow_rename: true)
        errors << "login: #{this_user.errors.full_messages.join(", ")}"
      end
    end

    begin
      obfuscate_profile(obfuscated_login)
    rescue ActiveRecord::ActiveRecordError => e
      errors << "profile: #{e.message}"
      exceptions << e
    end

    if errors.empty?
      flash[:notice] = "User #{display_login} has been obfuscated. New login: #{obfuscated_login}. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}"
    else
      error_messages = this_user.errors.full_messages.join(", ")
      if fix_emu_deprovisioning_errors_enabled? && error_messages.blank?
        error_messages = "User rename returned false with no validation errors. The user may have a stuck renaming flag or a conflicting namespace."
      end

      base_log_fields = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.user.id" => this_user.id,
        "gh.user.login" => this_user.login,
        "gh.user.new_login" => obfuscated_login,
        "gh.business.id" => this_user.enterprise_managed_business&.id,
      }
      base_log_fields["gh.user.renaming"] = this_user.renaming? if fix_emu_deprovisioning_errors_enabled?

      if exceptions.empty?
        GitHub.logger.error(
          "Error while obfuscating user login from stafftools",
          **base_log_fields,
          "exception.message" => error_messages,
        )
      end
      exceptions.each do |ex|
        GitHub.logger.error(
          "Error while obfuscating user login from stafftools",
          **base_log_fields,
          "exception.type" => ex.class.name,
          "exception.message" => ex.message,
        )
      end

      flash[:error] = "There was an error obfuscating login for user #{display_login}. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}. #{error_messages}"
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  # Checks whether the user's login has already been obfuscated by a previous
  # deprovisioning attempt. Obfuscated logins are SHA256 hex digests truncated
  # to fit within User::LOGIN_MAX_LENGTH (minus the enterprise shortcode suffix).
  # Historical obfuscations used the actual shortcode length, while current
  # obfuscations always use MAX_SHORTCODE_LENGTH, so we accept either stem length.
  def login_already_obfuscated?(user, suffix)
    login_stem =
      if suffix.present?
        user.login.delete_suffix("_#{suffix}")
      else
        user.login
      end

    # obfuscate_value truncates the SHA256 hex digest to LOGIN_MAX_LENGTH minus
    # the suffix length. Two suffix lengths are possible:
    #   - legacy: actual shortcode length + 1 (for the "_" separator)
    #   - current: MAX_SHORTCODE_LENGTH + 1
    # Legacy obfuscated logins may still exist, so we check both possible stem lengths.
    actual_suffix_length = suffix ? suffix.length + 1 : 0
    max_suffix_length = Business::MAX_SHORTCODE_LENGTH + 1
    stem_length_actual = User::LOGIN_MAX_LENGTH - actual_suffix_length
    stem_length_max = User::LOGIN_MAX_LENGTH - max_suffix_length

    login_stem.match?(/\A[0-9a-f]{#{stem_length_actual}}\z/) ||
      login_stem.match?(/\A[0-9a-f]{#{stem_length_max}}\z/)
  end

  def obfuscate_profile(obfuscated_login)
    this_user.update!(display_name: nil)

    profile = this_user.profile
    return if profile.nil?

    if profile.email.present?
      _, domain = profile.email.split("@", 2)
      if domain.present?
        profile.email = "#{obfuscated_login}@#{domain}"
      end
    end

    profile.save!
  end

  def fix_emu_deprovisioning_errors_enabled?
    FeatureFlag.vexi.enabled?(:fix_emu_deprovisioning_errors, nil, default: false)
  end
end
