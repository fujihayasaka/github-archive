# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class DecryptGhesColumns < GitHub::Transitions::Base

      def self.environment_key_ids
        GitHub.encrypted_column_keying_material
          .split(";")
          .map { |k| Base64.strict_decode64(k) }
          .map { |k| ActiveRecord::Encryption::Key.new(k).id }
          .map(&:to_s).join(", ")
      end

      def users_with_2fa
        User
          .joins(:two_factor_credential)
          .where.not(two_factor_credentials: { id: nil })
      end

      def mfa_recovery_secret_key_id_user_mapping
        users_with_2fa.each_with_object({}) do |user, output|
          begin
            key_id = Base64.strict_decode64(
              ActiveSupport::JSON.decode(user.two_factor_credential.ciphertext_for(:encrypted_recovery_secret))["h"]["i"]
            )
            output[key_id] ||= []
            output[key_id] << user
          rescue StandardError => e # rubocop:disable Lint/GenericRescue
            log("WARN: failed to decode 2FA credential ciphertext for user #{user.login} (#{e.class}) - already plaintext")
          end
        end
      end

      def weak_password_key_id_user_mapping
        User.all.each_with_object({}) do |user, output|
          begin
            ciphertext = user.ciphertext_for(:weak_password_check_result)
            next if ciphertext.nil?
            key_id = Base64.strict_decode64(ActiveSupport::JSON.decode(ciphertext)["h"]["i"])
            output[key_id] ||= []
            output[key_id] << user
          rescue StandardError => e # rubocop:disable Lint/GenericRescue
            log("WARN: failed to decode weak_password_check_result ciphertext for user #{user.login} (#{e.class}) - already plaintext")
          end
        end
      end

      def encrypted_totp_key_id(user)
        begin
          ciphertext = user.totp_app_registration.ciphertext_for(:encrypted_otp_secret)
          key_id = if ciphertext.present?
            Base64.strict_decode64(ActiveSupport::JSON.decode(ciphertext)["h"]["i"])
          else
            "unknown"
          end
          key_id
        rescue StandardError => e # rubocop:disable Lint/GenericRescue
          nil
          log("WARN: failed to decode totp_app_registration ciphertext for user #{user.login} (#{e.class}) - already plaintext")
        end
      end

      def perform
        # We only want to decrypt columns in enterprise
        if !GitHub.enterprise?
          log("This transition can only be run in enterprise. Aborting...")
          return
        end

        log("environment key IDs:")
        log(DecryptGhesColumns.environment_key_ids || "No keys found in environment")
        log("#{users_with_2fa.count} users with 2FA credentials found")

        log("processing each unique key ID for 2FA recovery secret records...")

        mfa_recovery_secret_key_id_user_mapping.keys.each do |key_id|
          log("#{mfa_recovery_secret_key_id_user_mapping[key_id].count} users with 2FA recovery secret using key ID #{key_id} found")
          if DecryptGhesColumns.environment_key_ids.include?(key_id)
            log("Key ID #{key_id} exists in the environment")
            log("Attemping to decrypt 2FA recovery secrets that are encrypted using key ID #{key_id}...")
            mfa_recovery_secret_key_id_user_mapping[key_id].each do |user|
              totp_key_id = encrypted_totp_key_id(user)
              if DecryptGhesColumns.environment_key_ids.include?(key_id)
                write_to(model_class: TwoFactorCredential) do
                  # This actually performs the decryption
                  # because column encryption is disabled for GHES
                  user.two_factor_credential.encrypt
                end
                write_to(model_class: TotpAppRegistration) do
                  # This actually performs the decryption
                  # because column encryption is disabled for GHES
                  user.totp_app_registration.encrypt
                end
                log("Success! decrypted 2FA for #{user.login}")
              else
                log("Failed to decrypt 2FA for #{user.login} because the TOTP was using a different key ID... disabling 2FA instead")
                ActiveRecord::Encryption.without_encryption do
                  write_to(model_class: TotpAppRegistration) do
                    write_to(model_class: TwoFactorCredential) do
                      user.two_factor_credential.destroy!
                    end
                  end
                end
                log("Success! disabled 2FA for #{user.login}")
              end
            end
          else
            log("Key ID #{key_id} DOES NOT exist in the environment")
            log("Attemping to delete 2FA credentials associated for 2FA recovery secrets encrypted using key ID #{key_id}...")
            mfa_recovery_secret_key_id_user_mapping[key_id].each do |user|
              log(" Disabling 2FA for #{user.login}...")
              ActiveRecord::Encryption.without_encryption do
                write_to(model_class: TotpAppRegistration) do
                  write_to(model_class: TwoFactorCredential) do
                    user.two_factor_credential.destroy!
                  end
                end
              end
              log("Success! disabled 2FA for #{user.login}")
            end
          end
        end

        log("Done with 2FA recovery secret records, moving onto weak_password_check_results...")

        log("#{User.count} users with weak_password_check_result found")
        log("Attempting to repair user records...") if weak_password_key_id_user_mapping.keys.compact.any?
        weak_password_key_id_user_mapping.keys.compact.each do |key_id|
          log("#{weak_password_key_id_user_mapping[key_id].count} users with weak_password_check_result records using key ID #{key_id} found")
          if DecryptGhesColumns.environment_key_ids.include?(key_id)
            log("Key ID #{key_id} exists in the environment")
            weak_password_key_id_user_mapping[key_id].each do |user|
              log("Attemping to decrypt weak password check result for #{user.login} using key ID #{key_id}...")
              write_to(model_class: User) do
                # This actually performs the decryption
                # because column encryption is disabled for GHES
                user.encrypt
              end
            end
          else
            log("Key ID #{key_id} DOES NOT exist in the environment")
            weak_password_key_id_user_mapping[key_id].each do |user|
              log(" Clearing weak password check result for #{user.login} using key ID #{key_id}...")
              ActiveRecord::Encryption.without_encryption do
                write_to(model_class: User) do
                  user.update_column(:weak_password_check_result, nil)
                end
              end
              log("Success! cleared weak_password_check_result for #{user.login}")
            end
          end
        end
        log("Done with weak_password_check_result records!")
        log("All done!")
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)
  GitHub::Transitions::DecryptGhesColumns.new(args).run
end
