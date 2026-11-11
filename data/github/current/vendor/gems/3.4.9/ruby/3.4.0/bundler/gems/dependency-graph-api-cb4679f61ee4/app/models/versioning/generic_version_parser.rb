module Versioning
  class GenericVersionParser

    # This is close enough to semver to distinguish more reliably between
    # versions and things like git shas, while still allowing some of the
    # flexibility allowed by Versioning::VersionParser::SEMANTIC_PATTERN.
    # It's based on the suggested regex linked from https://semver.org/, but
    # with minor and patch made optional and the remaining sections turned into
    # a wildcard.
    ALMOST_SEMVER = /\A
      (?<major>0|[1-9]\d*)
      (?:\.(?<minor>0|[1-9]\d*)
        (?:\.(?<patch>0|[1-9]\d*))?
      )?
      (?:[\.\-\+](?<rest>.*))?
      \Z
    /x

    def self.generate(allow_named_versions: false, primary_identifier:, minor: 0, patch: 0, additional_fields: [], prerelease: nil, metadata: nil)
      possible_version_string = [primary_identifier, minor, patch].join(".")
      return NamedVersion.new(name: primary_identifier) if valid_named_version?(allow_named_versions, possible_version_string)

      SemanticVersion.new(major: primary_identifier, minor: minor, patch: patch, additional_fields: additional_fields, prerelease: prerelease, metadata: metadata)
    end

    def self.valid_named_version?(allow_named_versions, version_string)
      allow_named_versions && !version_string.match?(ALMOST_SEMVER) && version_string.match?(/\A\S+$\z/)
    end
  end
end
