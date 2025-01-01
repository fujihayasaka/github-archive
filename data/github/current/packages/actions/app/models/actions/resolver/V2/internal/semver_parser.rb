# typed: true
# frozen_string_literal: true

class Actions::Resolver::V2::Internal::SemverParser

  # These are all slightly modified versions of the official semver regex.
  # Changes:
  # Adding Support for wildcards.
  # Changing `(?P)` to `(?)` since `P` isn't valid ruby regex syntax.
  # Changing `\A` and `\z` to `\A` and `\z` since these have different semantical meaning in ruby. https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-dotcom/regex/#anchors
  # Official Semver Regex Source https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
  FULL_SEMVER_REGEX = /\A(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?\z/
  PATCH_WILDCARD_SEMVER_REGEX = /\A(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.x\z/i
  MINOR_WILDCARD_SEMVER_REGEX = /\A(?<major>0|[1-9]\d*)\.x\z/i

  # These are handrolled regexes.
  FULL_CONVERTABLE_REPOSITORY_TAG_REGEX = /\Av(\d+).(\d+).(\d+)\z/i
  PATCH_WILDCARD_CONVERTABLE_REPOSITORY_TAG_REGEX = /\Av(\d+).(\d+)\z/i
  MINOR_WILDCARD_CONVERTABLE_REPOSITORY_TAG_REGEX = /\Av(\d+)\z/i

  # Returns the normalised semver for a given version.
  # if the version is not a semver and can't be converted to a semver, returns nil.
  # This method will return a semver if the version:
  # Is a full semver version (e.g. 1.2.3 or 1.2.3-alpha.1)
  # Is a partial semver with a wildcard (e.g. 1.2.x or 1.x which can be converted to 1.2.* and 1.* respectively)
  # Is a full version tag which can be converted to a semver (e.g. v1.1.1 which can be converted to 1.1.1)
  # Is a major and minor version tag which can be converted to a semver (e.g. v1.1 which can be converted to 1.1.*)
  # Is a major version tag which can be converted to a semver (e.g. v1 which can be converted to 1.*)
  #
  # Both the `v`-prefix and `x`-wildcard are case insensitive.
  sig { params(version: String).returns(T.nilable(String)) }
  def parse(version)
    if match = FULL_CONVERTABLE_REPOSITORY_TAG_REGEX.match(version)
      return "#{match.captures[0]}.#{match.captures[1]}.#{match.captures[2]}"
    end

    if match = PATCH_WILDCARD_CONVERTABLE_REPOSITORY_TAG_REGEX.match(version)
      return "#{match.captures[0]}.#{match.captures[1]}.*"
    end

    if match = MINOR_WILDCARD_CONVERTABLE_REPOSITORY_TAG_REGEX.match(version)
      return "#{match.captures[0]}.*"
    end

    if match = PATCH_WILDCARD_SEMVER_REGEX.match(version)
      return "#{match.captures[0]}.#{match.captures[1]}.*"
    end

    if match = MINOR_WILDCARD_SEMVER_REGEX.match(version)
      return "#{match.captures[0]}.*"
    end

    if version.match?(FULL_SEMVER_REGEX)
      version
    end
  end

  def is_full_semver?(version)
    version_without_v = version.sub(/\Av/, "") # strip off leading v if exists
    version_without_v.match?(FULL_SEMVER_REGEX)
  end
end
