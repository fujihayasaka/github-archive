# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Detect the license for this repository
    #
    # Uses the `licensee` gem to find a license file in the repository
    # and attemps to match it against a list of licenses
    #
    # Returns the license name if matched, "unknown" if an unknown license is found
    # or "no-license" when no license file exists whatsoever
    def detect_license(commit_oid)
      send_message(:detect_license, commit_oid)
    end

    def detect_licenses(commit_oid)
      send_message(:detect_licenses, commit_oid)
    end
  end
end
