# typed: true
# frozen_string_literal: true

module GitHub
  module CompromisedCredentials
    class CompromisedCredsProcessorJob < ApplicationJob
      queue_as :compromised_credentials_processing

      STATS_KEY = "compromised_creds_events.jobs.processed"

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      # Process a compromised credential event by decrypting and checking credentials
      #
      # encrypted_credential_pair: - The encrypted credential data from the event
      # credential_pair_id: - Unique identifier for this credential pair
      # partner_id: - The partner/data source identifier
      # breach_id: - The breach identifier this credential came from
      # encryption_key_version: - The version of encryption key used
      # request_id: - The request identifier for tracking
      # encryption_key: - RSA-encrypted AES-GCM key for decrypting the credential pair
      #
      # Returns nothing
      def perform(encrypted_credential_pair:, credential_pair_id:, partner_id:, breach_id:, encryption_key_version:, request_id:, encryption_key:)
        GitHub.logger.info(
          "Processing compromised credential",
          "gh.job.name": self.class.name,
          "gh.credential_pair_id": credential_pair_id,
          "gh.partner_id": partner_id,
          "gh.breach_id": breach_id,
          "gh.request_id": request_id,
          "gh.encryption_key_version": encryption_key_version
        )

        GitHub.dogstats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:started"])

        begin
          # Get RSA private key from vault based on encryption key version
          rsa_private_key = get_rsa_private_key(encryption_key_version)

          # Decrypt the RSA-encrypted AES-GCM key
          aes_gcm_key = decrypt_aes_key_with_rsa(encryption_key, rsa_private_key)

          # Decrypt the credential pair using the AES-GCM key
          handle, password = decrypt_credential_pair(encrypted_credential_pair, aes_gcm_key)

          # Skip processing if we don't have valid credentials after decryption
          if handle.blank? || password.blank?
            GitHub.logger.warn(
              "Skipping compromised credential with blank handle or password after decryption",
              "gh.job.name": self.class.name,
              "gh.credential_pair_id": credential_pair_id,
              "gh.partner_id": partner_id
            )
            GitHub.dogstats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:blank_credentials"])
            return
          end

          # this is a special feature flag, to restrict legitimately processing
          # the compromised credentials based on the incoming handle
          # note/important: "handle" from compromised credentials is meant to be the email (from MACE)
          # `CompromisedCredentialsService.process_credentials_batch` handles "handle" being a username _or_ email which is cool/fine
          # but for the sake of simplicity for restricting this, we're only checking the username
          user = User.find_by(login: handle)
          unless user&.feature_flag_enabled?(:compromised_creds_processor_by_handle, default: false)
            GitHub.logger.info(
              "Skipping compromised credential processing for handle",
              "gh.job.name": self.class.name,
              "gh.credential_pair_id": credential_pair_id,
              "gh.partner_id": partner_id,
              "gh.handle": handle,
              "gh.user_found": user.present?,
            )
            GitHub.dogstats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:feature_not_enabled_for_handle"])
            return
          end

          # Process the credentials using the existing service
          CompromisedCredentialsService.process_credentials_batch(
            credentials: [[handle, password]],
            datasource_name: partner_id,
            version: breach_id
          )

          GitHub.logger.info(
            "Successfully processed compromised credential",
            "gh.job.name": self.class.name,
            "gh.credential_pair_id": credential_pair_id,
            "gh.partner_id": partner_id
          )

          GitHub.dogstats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:success"])

        rescue OpenSSL::Cipher::CipherError, ArgumentError, Yajl::ParseError, RuntimeError => e
          GitHub.logger.error(
            "Failed to process compromised credential",
            "gh.job.name": self.class.name,
            "gh.credential_pair_id": credential_pair_id,
            "gh.partner_id": partner_id,
            "gh.error": e.message
          )

          GitHub.dogstats.increment(STATS_KEY, tags: ["partner_id:#{partner_id}", "status:error"])

          Failbot.report!(e, {
            credential_pair_id: credential_pair_id,
            partner_id: partner_id,
            breach_id: breach_id,
            request_id: request_id
          })

          # Re-raise to ensure proper retry behavior
          raise
        end
      end

      private

      # Get the RSA private key from vault based on the encryption key version
      #
      # encryption_key_version: - The version identifier for the encryption key
      #
      # Returns the RSA private key as an OpenSSL::PKey::RSA object
      def get_rsa_private_key(encryption_key_version)
        # Get the vault key configuration from pre-parsed GitHub config
        config = GitHub.compromised_credentials_encryption_keys
        raise "Missing compromised credentials encryption keys configuration" if config.blank?

        begin
          versions = config["versions"] || {}

          # Convert encryption_key_version to string for lookup
          version_key = encryption_key_version.to_s

          unless versions.key?(version_key)
            raise "Encryption key version #{encryption_key_version} not found in configuration"
          end

          # Get the private key material for decryption
          key_data = versions[version_key]
          private_key = key_data["private_key"]

          if private_key.blank?
            raise "No private key found for encryption key version #{encryption_key_version}"
          end

          OpenSSL::PKey::RSA.new(private_key)

        rescue Yajl::ParseError => e
          raise "Failed to parse compromised credentials encryption keys configuration: #{e.message}"
        rescue ArgumentError, RuntimeError => e
          raise "Failed to get decryption key for version #{encryption_key_version}: #{e.message}"
        end
      end

      # Decrypt an RSA-encrypted AES-GCM key
      #
      # encrypted_aes_key: - The RSA-encrypted AES-GCM key (base64 encoded)
      # rsa_private_key: - The RSA private key object
      #
      # Returns the decrypted AES-GCM key as raw bytes
      def decrypt_aes_key_with_rsa(encrypted_aes_key, rsa_private_key)
        begin
          # Decode the base64-encoded encrypted AES key
          encrypted_data = Base64.strict_decode64(encrypted_aes_key)

          # Decrypt using RSA private key with PKCS#1 padding
          rsa_private_key.private_decrypt(encrypted_data)

        rescue ArgumentError => e
          if e.message.include?("invalid base64")
            raise "Invalid Base64 encoding in encrypted AES key: #{e.message}"
          else
            raise "Invalid encrypted AES key format: #{e.message}"
          end
        rescue OpenSSL::PKey::RSAError => e
          raise "RSA decryption failed: #{e.message}"
        rescue RuntimeError => e
          raise "Unexpected error during RSA decryption: #{e.message}"
        end
      end

      # Decrypt an encrypted credential pair using standard AES-GCM decryption
      #
      # encrypted_credential_pair: - The encrypted data (base64 encoded)
      #                             Format: [1-byte schema version][12-bytes IV][encrypted payload]
      # decryption_key: - The decryption key (raw bytes)
      #
      # Returns a two-element array [handle, password]
      def decrypt_credential_pair(encrypted_credential_pair, decryption_key)
        begin
          # Decode the base64-encoded encrypted data
          data = Base64.strict_decode64(encrypted_credential_pair)

          # Validate minimum size: 1 byte schema + 12 bytes IV + at least some encrypted data + 16 bytes auth tag
          if data.size < 1 + 12 + 16 + 1 # schema + IV + auth tag + minimum payload
            raise "Invalid encrypted credential format: too short"
          end

          # Extract schema version (first byte)
          schema_byte = data.byteslice(0, 1)
          raise "Missing schema version byte" if schema_byte.nil?

          schema_version = schema_byte.unpack1("C")

          if schema_version != 1
            raise "Unsupported schema version: #{schema_version}, expected 1"
          end

          # Extract IV (next 12 bytes)
          iv = data.byteslice(1, 12)

          # Extract auth tag (last 16 bytes)
          auth_tag = data.byteslice(-16, 16)

          # Extract the encrypted payload (everything between IV and auth tag)
          payload_offset = 1 + 12 # schema + IV
          payload_size = data.bytesize - payload_offset - 16 # total - schema - IV - auth_tag
          encrypted_payload = data.byteslice(payload_offset, payload_size)

          # Use AES-GCM decryption
          aes = OpenSSL::Cipher::AES.new(256, :GCM)
          aes.decrypt
          aes.key = decryption_key
          aes.iv = iv
          aes.auth_tag = auth_tag

          # Decrypt the payload
          plaintext = aes.update(encrypted_payload) + aes.final

          # Parse the decrypted data as JSON to extract handle and password
          credential_data = GitHub::JSON.parse(plaintext)
          handle = credential_data["handle"]
          encoded_password = credential_data["password"]

          if handle.blank? || encoded_password.blank?
            raise "Missing handle or password in credential data"
          end

          # Decode the Base64 encoded password
          password = Base64.strict_decode64(encoded_password)

          [handle, password]

        rescue OpenSSL::Cipher::CipherError => e
          raise "Decryption failed: #{e.message}"
        rescue Yajl::ParseError => e
          raise "Failed to parse decrypted credential data: #{e.message}"
        rescue ArgumentError => e
          if e.message.include?("invalid base64")
            raise "Invalid Base64 encoding in credential data: #{e.message}"
          else
            raise "Invalid data format: #{e.message}"
          end
        rescue RuntimeError => e
          raise "Unexpected error during decryption: #{e.message}"
        end
      end
    end
  end
end
