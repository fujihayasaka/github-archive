require "securerandom"

module Enterprise
  module Crypto
    # A Customer represents the cryptographic data associated with an
    # enterprise customer: secret & public key data, and identification data.
    # Customer has methods for generating new customer data, and loading
    # customer data from raw key data.
    #
    class Customer < Struct.new(:name, :email, :uuid, :secret_key_data, :public_key_data)

      # Creates a new customer's encryption data.
      #
      # name  - name of the customer as a String.
      # email - email of the customer as a String.
      #
      def self.generate(name, email, vault = Crypto.customer_vault)
        uuid, public_key, secret_key_data, public_key_data = SecureRandom.uuid, nil, nil, nil

        Crypto.with_vault(vault) do
          public_key = vault.generate_customer_key(name, email, uuid)

          secret_key_data = vault.export_secret(public_key.fingerprint)
          public_key_data = vault.export_public(public_key.fingerprint)
        end

        new(name, email, uuid, secret_key_data, public_key_data)
      end

      # Deserializes a customer's encryption data.
      #
      # secret_key_data - the secret data portion of a customer's key as a String.
      # public_key_data - the public data portion of a customer's key as a String.
      #
      def self.from(secret_key_data, public_key_data, vault = Crypto.customer_vault)
        key = Crypto.with_vault(vault) do
          fingerprint = vault.import_key(secret_key_data)
          public_key  = vault.find_public_key(vault.import_key(public_key_data))

          Vault.verify_key_fingerprint!(public_key, fingerprint)
          Vault.verify_key_signature!(public_key, vault.public_key)

          vault.find_private_key(fingerprint)
        end

        new(key.name, key.email, key.comment, secret_key_data, public_key_data)
      end

      # The customer's public key.
      #
      def public_key(vault = Crypto.customer_vault)
        Crypto.with_vault(vault) do
          fingerprint = vault.import_key(public_key_data)

          vault.find_public_key(fingerprint)
        end
      end

      # The customer's secret key.
      #
      def secret_key(vault = Crypto.customer_vault)
        Crypto.with_vault(vault) do
          fingerprint = vault.import_key(secret_key_data)

          vault.find_secret_key(fingerprint)
        end
      end

      # Creates a new License instance for this customer.
      #
      def generate_license(*a)
        License.generate(self, *a)
      end
    end
  end
end
