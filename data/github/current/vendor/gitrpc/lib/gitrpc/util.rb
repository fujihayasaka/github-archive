# frozen_string_literal: true
require "time"

require "gitrpc/util/hashcache"
require "rugged"

module GitRPC
  # General Git related utility functions that are useful all over the place.
  # This is mixed into the various places that use it explicitly to ensure the
  # methods are available.
  module Util
    extend self

    VALID_HEX_OBJECT_ID_SIZES = [40, 64].freeze
    FULL_OID_REGEXP = /[a-f0-9]{40}(?:[a-f0-9]{24})?/
    FULL_OID_STANDALONE_REGEXP = /\A[a-f0-9]{40}(?:[a-f0-9]{24})?\z/
    NULL_OID_REGEXP = /0{40}(?:0{24})?/
    NULL_OID_STANDALONE_REGEXP = /\A0{40}(?:0{24})?\z/

    # Check if a given string is a valid full object ID.
    #
    # oid - String to check.
    #
    # Returns true when oid is exactly 40 or 64 valid object ID characters.
    def valid_full_oid?(oid)
      oid.is_a?(String) && VALID_HEX_OBJECT_ID_SIZES.include?(oid.bytesize) && oid.b =~ FULL_OID_STANDALONE_REGEXP
    end

    # Raise an InvalidFullOid exception if the given string is
    # not a valid full object ID.
    def ensure_valid_full_oid(oid)
      if !valid_full_oid?(oid)
        raise InvalidFullOid, "wrong argument type #{oid.inspect} (expected 40c or 64c String OID)"
      end
    end

    # Check if a given string is a valid object ID.
    #
    # oid - String to check.
    #
    # Returns true when oid is at least 7 and no more than 64 object ID characters.
    def valid_oid?(oid)
      oid.is_a?(String) && oid.b =~ /\A[a-f0-9]{7,64}\Z/
    end

    # Raise an InvalidOid exception if the given string is not a valid
    # abbreviated or full object ID.
    def ensure_valid_oid(oid)
      if !valid_oid?(oid)
        raise InvalidOid, "wrong argument type #{oid.inspect} (expected abbreviated or full String OID)"
      end
    end

    # Check whether the given string is a valid reference name
    #
    # refname - String to check.
    #
    # Returns true if it's valid, false if not
    def valid_refname?(refname)
      Rugged::Reference.valid_name?(refname)
    end

    # Check if a given string is a null (all-zeros) object ID.
    #
    # oid - String to check.
    #
    # Returns true when the string is a valid object ID and is all zeros.
    def null_oid?(oid)
      oid =~ NULL_OID_STANDALONE_REGEXP
    end

    # Normalizes a path into a format acceptable to git. This will
    # remove leading slashes and convert empty or '.' paths to nil.
    #
    # path - The path String or nil.
    #
    # Return the normalized path String or nil.
    def normalize_path(path)
      return if path.nil?

      path = path.b.sub(/^\//, "")
      path = nil if path.empty? || path == "."
      path
    end

    # Check whether the given string is acceptable as a revision.  The checking
    # done is currently minimal, but may become stricter in the future.
    #
    # rev - String to check.
    #
    # Returns true if it's valid, false if not
    def sanitary_revspec?(rev)
      # A ref and path need not be in UTF-8.  Duplicate it in case it's frozen
      # and force it to binary so we can compare it.
      rev = rev.to_s.dup.force_encoding("ASCII-8BIT")

      # nil and the empty string are not valid refspecs.
      return false if rev.empty?

      # Don't allow a dot-dot in a revision, but do allow it in the path form in
      # the case of REVISION:PATH...WITH...DOTS.  Git will never process a .. in
      # a path component in this syntax.
      revision_component = rev.split(":")[0]

      # The ":" string returns nil and not empty for the split.
      return false if revision_component.nil?

      !revision_component.include?("..")
    end

    # Check whether the argument contains potentially unsafe components. For
    # example, ensure that 'argument' can't be interpreted as an argument to a
    # Git subcommand.
    #
    # Note that this is a temporary measure before using '--end-of-arguments' in
    # our fork of Git. Once this change lands in our fork, we can remove this
    # method and ensure that no user-supplied arguments appear in an unsafe
    # fashion on the left-hand side of '--end-of-arguments'.
    #
    # Returns true if it's valid, false if not.
    def valid_sanitary_argument?(argument)
      argument.is_a?(String) &&
        !argument.start_with?("-") &&
        !argument.include?("..")
    end

    def ensure_sanitary_argument(argument)
      if !valid_sanitary_argument?(argument)
        raise UnsafeArgument, argument
      end
    end

    # Raise a InvalidReferenceName exception if the given string is not a valid
    # reference name
    def ensure_valid_refname(refname)
      if !valid_refname?(refname)
        raise InvalidReferenceName, refname
      end
    end

    def valid_commitish?(commitish)
      # HACK: abide by the branch name rules in 'sha1-name.c' and disallow
      # names beginning with '-'
      !commitish.start_with?("-") && (
        valid_oid?(commitish) || valid_refname?(commitish) ||
          # HACK: handle an unqualified 'commitish' argument by prepending 'refs/'
          # to the beginning of it, so that Rugged treats it as a
          # pseudo-fully qualified reference name.
          #
          # Note that we do _not_ return the argument with 'refs/' prepended to it
          # (that is, we do not modify the argument), we are merely checking to
          # see if it looks like a valid fully qualified reference name for our
          # own purposes.
          valid_refname?("refs/#{commitish}")
        )
    end

    def ensure_valid_commitish(commitish)
      if !valid_commitish?(commitish)
        raise InvalidCommitish, commitish
      end
    end

    # Clamp a Time object to the minimum value that Git can handle, preserving
    # the time zone of the original date.
    #
    # Git can't handle any date strings before 1970, even if the time zone
    # offset makes it so that the actual Unix timestamp is non-negative. So, if
    # the UTC offset is negative, the minimum timestamp is 0 + that offset.
    # Otherwise, the minimum Unix timestamp is 0.
    #
    # Git also can't handle any date strings after 2099-12-31 23:59:59Z.
    # Therefore, we clamp the maximum date to this date.
    #
    # Returns the clamped Time object.
    def clamp_git_time(date)
      # Why the strange min date?
      min_date = Time.at([0, -date.utc_offset].max, in: date.utc_offset)
      min_clamped_date = [min_date, date].max

      # 2099-12-31 23:59:59Z
      max_date = Time.at(4102444799 - date.utc_offset, in: date.utc_offset)
      [min_clamped_date, max_date].min
    end

    # Convert an ISO8601-formatted string to a Time object.
    #
    # Unlike the normal Time.iso8601 or Time.xmlschema methods, this:
    # - preserves the UTC offset if we're on 1.9+
    # - supports all three official ISO8601 UTC offset formats (+05:00, +0500,
    #   and +05) instead of just +05:00
    #
    # iso8601_string - String to convert to a time object.
    #
    # Returns a Time object.
    def iso8601(iso8601_string)
      return iso8601_string if iso8601_string.is_a?(Time)

      if utc_offset = utc_offset_for(iso8601_string)
        full_utc_offset = normalized_utc_offset(utc_offset)

        # Normalize the ISO8601 string so that Time.iso8601 can handle it
        iso8601_string = iso8601_string.sub(utc_offset, full_utc_offset)
        time = Time.iso8601(iso8601_string)

        # Use the UTC offset in the time object if possible
        time = time.getlocal(full_utc_offset)
      else
        time = Time.iso8601(iso8601_string)
      end

      time
    end

    # Internal: Extract the UTC offset from an ISO8601 string
    #
    # iso8601_string - String to extract the UTC offset from.
    #
    # Returns a string UTC offset in one of the three valid forms, or nil if
    # there is none.
    def utc_offset_for(iso8601_string)
      if match_group = iso8601_string.match(/[-+]\d\d(:?\d\d)?$/)
        # There's a UTC offset.
        match_group[0]
      else
        # It's a UTC time.
        nil
      end
    end

    # Internal: Convert a string UTC offset to one that Time.iso8601 can handle.
    #
    # utc_offset - UTC offset string to normalize
    #
    # Supported formats:
    #   +05:00
    #   +0500
    #   +05
    #
    # Returns a normalized string UTC offset or nil if it doesn't match a
    # supported format.
    def normalized_utc_offset(utc_offset)
      case utc_offset.length
      when 6
        # Format: +05:00
        utc_offset
      when 5
        # Format: +0500
        utc_offset.dup.insert(3, ":")
      when 3
        # Format: +05
        utc_offset + ":00"
      else
        # Something else (probably 'Z' for a UTC time)
        nil
      end
    end

    # Internal: Convert a Time object into a simple unixtime with offset.
    #
    # time - A Time object.
    #
    # Returns a [unixtime, offset] array where both unixtime and offset are
    # integers. The unixtime is the number of seconds since midnight 1970 UTC.
    # The offset is the timezone offset, also in seconds.
    def time_to_unixtime(time)
      [time.to_i, time.utc_offset]
    end

    # Internal: Convert a simple unixtime with offset array into a Time object.
    #
    # unixtime - A [unixtime, offset] array where both unixtime and offset are
    #            integers. The unixtime is the number of seconds since midnight
    #            1970 UTC; offset is the timezone offset in seconds.
    #
    # Returns a Time object with the utc offset set to the specified value.
    # Under Ruby 1.8.7, offsets are not supported and times are always returned
    # in UTC.
    #
    # Raises ArgumentError when the offset value is more than 24 hours.
    def unixtime_to_time(unixtime)
      t, offset = unixtime
      time = Time.at(t)
      if time.utc_offset != offset
        if offset == 0
          time.utc
        else
          time.localtime(offset)
        end
      end
      time
    end

    # Internal: Turn hash string keys into symbols.
    #
    # hash - Hash to convert.
    #
    # Returns a new hash with all symbol keys.
    def symbolize_keys(hash)
      new = {}
      hash.each { |key, val| new[key.to_sym] = val }
      new
    end

    # Internal: Turn hash symbol keys into strings.
    #
    # hash - Hash to convert.
    #
    # Returns a new hash with all symbol keys.
    def stringify_keys(hash)
      new = {}
      hash.each { |key, val| new[key.to_s] = val }
      new
    end

    # Public: Convert an options hash to command line arguments.
    def options_to_argv(options)
      argv = []
      options.each do |k, val|
        key = k.to_s.tr("_", "-")

        case val
        when true
          if key.size == 1
            argv << "-#{key}"
          else
            argv << "--#{key}"
          end
        when false
          # ignore
        else
          if key.size == 1
            argv << "-#{key}"
            argv << val.to_s
          else
            argv << "--#{key}=#{val}"
          end
        end
      end
      argv
    end

    # Public: convert an options hash by removing the empty pathspec.
    def convert_empty_pathspec(options)
      if options && options[:path] == ""
        options.delete(:path)
      end
      options
    end

    # Handles error output from `git-merge-base --is-ancestor` and `git-branch-contains`/`git-tag-contains`.
    # Could be tweaked carefully to handle output from other commands as well.
    def handle_missing_or_wrong_object_type(res)
      if res["err"] =~ /is a (blob|tree|tag), not a commit/
        raise GitRPC::InvalidObject, res["err"]
      elsif res["err"] =~ /Not a valid commit name (#{FULL_OID_REGEXP})/ || res["err"] =~ /no such commit (#{FULL_OID_REGEXP})/
        raise GitRPC::ObjectMissing.new(res["err"], $1)
      else
        raise GitRPC::Error, res["err"]
      end
    end

    READ_REFS_FILTERS = %w[default extended all].freeze

    # Raise an ArgumentError if the given string is not a valid filter for
    # 'read_refs'.
    def ensure_valid_read_refs_filter(filter)
      if !READ_REFS_FILTERS.include?(filter)
        raise ArgumentError, "Filter must be one of default, extended, or all"
      end
    end

    # Raised when a repack operation fails.
    class RepackFailed < StandardError
    end

    # Raised when a repack operation is locked
    class RepackLocked < StandardError
    end

    def lock_conflict_failure?(res)
      # `git nw-repack` exits 2 if there is a lock conflict.
      res["status"] == 2
    end

    # Raise appropriate errors when a repack fails, so we can
    # distinguish between repacks that should be failed, and ones that
    # should be retried.  Can wrap both nw_gc and nw_repack
    # operations.
    #
    # Raises a RepackLocked exception when one or more replicas are
    # locked and a RepackFailed exception when the repack fails on all
    # replicas.  Otherwise raises or returns the result from the
    # wrapped nw_gc or nw_repack operation.
    def with_repack_error_handler
      res = yield
      raise RepackLocked.new(res.slice("ok", "status")) if res && lock_conflict_failure?(res)
      raise RepackFailed.new(res.slice("ok", "status")) if res && !res["ok"]
      res

    # Raise a RepackLocked error if 1 <= N < nreplicas servers had a lock
    # conflict and the rest succeeded.
    rescue GitRPC::Protocol::DGit::ResponseError => e
      if locked = e.answers.values.find { |ans| !ans["ok"] && lock_conflict_failure?(ans) }
        if e.answers.values.all? { |ans| ans["ok"] || lock_conflict_failure?(ans) }
          raise RepackLocked.new(locked.slice("ok", "status"))
        end
      end
      raise
    end
  end
end
