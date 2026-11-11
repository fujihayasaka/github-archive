# frozen_string_literal: true

# All version ranges from GitHub are in Ruby notation, so we need
# to parse them into language specific notations in some cases.
module GitHub
  class VersionRange
    class InvalidRangeError < StandardError; end

    REQUIREMENTS_FORMAT = /
      \A
      # Two basic versions, those with the comma, and those without
      (
        (?: # version without comma
          (?<only_operator>=|<|<=|>|>=)
          (?:[ ])
          (?<only_version>\d[^\s,]*)
        )
        |
        (?: # version with comma
          # restrict to starting with greater-than or greater-than-or-equal-to
          (?<lower_operator>>|>=)
          (?:[ ])
          (?<lower_version>\d[^\s,]*)
          ,
          (?:[ ])
           # likewise upper operator must be less-than
          (?<upper_operator><|<=)
          (?:[ ])
          (?<upper_version>\d[^\s,]*)
        )
      )
      \z
    /x

    attr_reader :version_range_string, :package_manager

    def self.convert_for_dependabot(version_range_string:, package_manager:)
      new(version_range_string).convert_for_dependabot(package_manager)
    end

    def initialize(version_range_string)
      unless REQUIREMENTS_FORMAT.match? version_range_string
        raise InvalidRangeError,
              "#{version_range_string} is not valid"
      end

      @version_range_string = version_range_string
    end

    def convert_for_dependabot(package_manager)
      case package_manager
      when PackageManagers::NPM_AND_YARN, PackageManagers::BUN
        convert_to_npm
      when PackageManagers::MAVEN
        convert_to_maven
      else
        version_range_string
      end
    end

    private

    def convert_to_maven
      lower_boundary, upper_boundary = version_range_string.split(",").
                                       map(&:strip)

      if upper_boundary.nil?
        if lower_boundary.start_with?(/>=?/)
          lower_boundary = convert_to_maven_low_boundary(lower_boundary)
          upper_boundary = ")"
        elsif lower_boundary.start_with?(/<=?/)
          upper_boundary = convert_to_maven_high_boundary(lower_boundary)
          lower_boundary = "("
        else
          # If we just have a single version, strip any leading `=`
          lower_boundary.gsub!(/=\s*/, "")
        end
      else
        lower_boundary = convert_to_maven_low_boundary(lower_boundary)
        upper_boundary = convert_to_maven_high_boundary(upper_boundary)
      end

      [lower_boundary, upper_boundary].compact.join(",")
    end

    def convert_to_maven_low_boundary(string)
      if string.start_with?(/>=/)
        "[" + string.gsub(/>=\s*/, "").to_s
      else
        "(" + string.gsub(/>\s*/, "").to_s
      end
    end

    def convert_to_maven_high_boundary(string)
      if string.start_with?(/<=/)
        string.gsub(/<=\s*/, "").to_s + "]"
      else
        string.gsub(/<\s*/, "").to_s + ")"
      end
    end

    def convert_to_npm
      version_range_string.gsub(/,\s*/, " ")
    end
  end
end
