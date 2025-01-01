# frozen_string_literal: true

module AdvisoryDB
  # An abstraction for a single entity in the format `[operator ]<version>`. Not a list of multiple ranges.
  # For example: `1.2.3`; or `<= 4.5.6`; or `=7.8.9`
  class VersionRange
    attr_accessor :operator

    def initialize(version_range_string)
      match_data = version_range_string.strip.match(/^(?<operator>>|>=|<|<=|=)? ?(?<version>.*)/)
      @operator = match_data[:operator]
      @version = match_data[:version]
    end

    def to_s
      if @operator
        "#{@operator} #{@version}"
      else
        @version
      end
    end
  end
end
