module Enterprise
  module Crypto
    # A Vault for creating and extracting enterprise licenses.
    #
    class LicenseVault < Vault

      # Creates an encrypted and signed license object from
      # the raw license data.
      #
      # raw - The license data as a String.
      #
      alias_method :generate_license, :encrypt_and_sign

      # Returns the decrypted and verified license data.
      #
      # object  - signed license data.
      #
      alias_method :read_license, :decrypt_and_verify
    end
  end
end
