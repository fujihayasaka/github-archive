# typed: true
# frozen_string_literal: true

module Elastomer
  module Slicers

    class AuditLogDateSlicer < DateSlicer

      # we have the oddball `audit_log-2012` index to contend with
      YEAR_SLICE = "2012".freeze

      # Assign the index name. This must be an String value that contains only
      # word characters in the set [a-zA-Z0-9_] and starts with alpha character.
      # Setting the index name to `nil` will clear the attribute.
      #
      # Raises an ArgumentError if the index name is not valid.
      def index=(obj)
        if obj.nil?
          @index = nil

        elsif obj.is_a?(Class) && obj == ::Elastomer::Indexes::AuditLog
          @index = obj.name&.demodulize.underscore
          @index = "#{@index}#{postfix_match}" if postfix

        elsif obj.is_a?(String) && obj =~ /\A#{index_match}\z/i
          @index =
            if postfix && obj !~ /#{postfix_match}\Z/
              "#{obj}#{postfix_match}"
            else
              obj
            end
        else
          raise ArgumentError, "unrecognized index name: #{obj.inspect}"
        end
      end

      # Assign the slice name. This must be an String value that contains only
      # word characters in the set [a-zA-Z0-9_]. Setting the slice name to `nil`
      # will clear the attribute.
      #
      # Raises an ArgumentError if the slice name is not valid.
      def slice=(str)
        if str.nil?
          @slice = nil
        elsif str.is_a?(String) && (str =~ /\A#{slice_match}\z/ || str == YEAR_SLICE)
          @slice = str
        else
          raise ArgumentError, "unrecognized slice name: #{str.inspect}"
        end
      end

      # Constructs a slice name based on the given value. Subclasses can override
      # this method to implement their own slicing strategies.
      #
      # value - Either an Integer number of milliseconds or a Time instance.
      #
      # Returns the slice name as a String.
      # Raises an ArgumentError if the value could not be converted to a slice.
      def slice_from_value(value)
        return value if value.is_a?(String) && (value =~ /\A#{slice_match}\z/ || value == YEAR_SLICE)

        time =
          case value
          when Integer; Audit.milliseconds_to_time(value)
          when Time; value
          else
            raise ArgumentError, "time value required but #{value.inspect} was given"
          end

        if time.year.to_s == YEAR_SLICE
          YEAR_SLICE.dup
        else
          time.strftime("%Y-%m")
        end
      end

      # Internal: This method parses the given full index name and parses out and
      # returns the four index name parts.
      #
      # str - The full name of the index as a String
      #
      # Returns the four index name parts as an Array: [index, index_version, slice, slice_version]
      # Raises an ArgumentError if the input string could not be parsed.
      def validate_fullname(str)
        index, index_version, slice, slice_version = super(str)

        # This is here because of our `audit_log-2012` index which is different
        # from all our other YYYY-MM based audit log indices. This special case
        # can be removed when that index has been deleted.
        if index_version == YEAR_SLICE
          slice, index_version = index_version, nil
        end

        [index, index_version, slice, slice_version]
      rescue ArgumentError
        audit_log_validation(str)
      end

      # Internal: Fall back to matching on `<index_name>-<slice_name>` for our
      # legacy `audit_log-2016-12` index names.
      #
      # str - The full name of the index as a String
      #
      # Returns the four index name parts as an Array: [index, index_version, slice, slice_version]
      # Raises an ArgumentError if the input string could not be parsed.
      def audit_log_validation(str)
        rgxp = %r/\A
                  (?<index>#{index_match})                       # index name
                  #{postfix_match}                               # `postfix` used for testing
                  (?:-(?<index_version>#{version_match}))?       # optional index version number
                  (?:-(?<slice>#{slice_match})                   # non-optional slice name
                  (?:-(?<slice_version>#{version_match}))?)?     # optional slice version number
                \Z/ix                                            # case insensitive, extended regexn

        match = rgxp.match(str)
        raise ArgumentError, "unrecognized full-name: #{str.inspect}" if match.nil?

        index = postfix ? "#{match[:index]}#{postfix_match}" : match[:index]
        [index, match[:index_version], match[:slice], match[:slice_version]]
      end

      # Internal: Matches on slice names formatted as YYYY-MM. This is a loose
      # match so we are not validating strict year conformancy.
      def slice_match
        "(?:\\d{4}-(?:0[1-9]|1[0-2]))|#{YEAR_SLICE}"
      end

      # Internal: Take a value and return a Time instance that is pinned to the
      # first day of the month for that particular value.
      #
      # value - a String or a Time
      #
      # Returns a Time instance for the first day of the month.
      def time_from_value(value)
        year = month = nil

        if value.is_a?(String) && value =~ /\A#{slice_match}\z/
          year, month = value.split("-")
          year  = year.to_i
          month = month ? month.to_i : 6
        elsif value == YEAR_SLICE
          year  = YEAR_SLICE.to_i
          month = 6
        elsif value.is_a?(Time)
          year  = value.year
          month = value.month
        else
          raise ArgumentError, "unrecognized time value: #{value.inspect}"
        end

        Time.utc(year, month)
      end

      # Checks if the current index slice, example "audit-logs-2017-01"
      # matches the created_at (or any date) in a document.
      #
      # Returns true if the entry_date is valid for the slice
      def is_entry_date_valid_for_slice?(entry_date)
        return false if !entry_date || !slice
        year, month = slice.split("-")
        (entry_date.year == year.to_i) && (entry_date.month == month.to_i) || (entry_date.year == YEAR_SLICE.to_i)
      end
    end
  end
end
