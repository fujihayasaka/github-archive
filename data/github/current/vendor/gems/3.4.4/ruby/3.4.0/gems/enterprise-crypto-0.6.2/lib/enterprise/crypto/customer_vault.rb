module Enterprise
  module Crypto
    # A Vault for working with customer GPG keys. Used to
    # generate and verify a customer keypair.
    #
    class CustomerVault < Vault

      # Generate a new customer keypair signed by the customer key.
      #
      # name      - The Name-Real segment.
      # email     - The Name-Email segment.
      # comments  - The Name-Comments segment.
      #
      def generate_customer_key(name, email, comments)
        with_vault do
          with_context do |context|
            context.generate_key(customer_key_params(name, email, comments))
          end

          unsigned_key = find_public_key(email)
          signed_key   = sign_with_customer_key(unsigned_key)

          signed_key
        end
      end

      def sign_with_customer_key(key)
        command = %w[gpg]
        command << "--homedir=#{home_dir}"
        command << '--batch' << '--yes'
        command << "--default-key=#{secret_key.fingerprint}"
        command << "--sign-key #{key.fingerprint}"
        command << "1>/dev/null" << "2>&1"

        ## GPGME doesn't support key signing, so we must shell out :(
        system(command.join(' '))

        find_public_key(key.fingerprint)
      end

      def customer_key_params(name, email, comments)
        return <<-XML.chomp
<GnupgKeyParms format="internal">
Key-Type: RSA
Key-Length: #{Crypto.key_size}
Subkey-Type: RSA
Subkey-Length: #{Crypto.key_size}
Name-Real: #{name}
Name-Comment: #{comments}
Name-Email: #{email}
Expire-Date: 0
</GnupgKeyParms>
        XML
      end
    end
  end
end
