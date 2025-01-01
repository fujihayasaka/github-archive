module Enterprise
  module Crypto
    module VaultValidator
      extend self

      def validate!(vault)
        check_master_key(vault) unless vault.master_key.nil?
        check_public_key(vault) unless vault.public_key.nil?
        check_secret_key(vault) unless vault.secret_key.nil?
      end

      def check_master_key(vault)
        Vault.verify_key_fingerprint!(vault.master_key, Vault::MASTER_FINGERPRINT)
      end

      # The public key should be signed by the master key
      def check_public_key(vault)
        Vault.verify_key_signature!(vault.public_key, vault.master_key)
      end

      # The secret key fingerprint & public key fingerprint should match
      def check_secret_key(vault)
        Vault.verify_key_fingerprint!(vault.secret_key, vault.public_key.fingerprint)
      end
    end
  end
end
