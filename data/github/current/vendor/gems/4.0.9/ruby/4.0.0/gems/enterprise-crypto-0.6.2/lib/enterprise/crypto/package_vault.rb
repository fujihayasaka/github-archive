module Enterprise
  module Crypto
    # A Vault for creating and extracting update packages.
    #
    class PackageVault < Vault

      # Creates an encrypted and signed enterprise package.
      #
      # raw - The package data as a String.
      #
      alias_method :generate_package, :encrypt_and_sign

      # Returns the decrypted and verified package data.
      #
      # object  - signed package data.
      alias_method :read_package, :decrypt_and_verify

      def new_signed_data(object)
        GPGME::Data.from_io(object)
      end
    end
  end
end
