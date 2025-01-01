# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SpokesAPI
  class << self
    # Timeout, in seconds, for requests made to Spokes API.
    #
    # When set, this timeout will be used in place of Spokes API's internal default.
    attr_accessor :timeout

    # Quality of service, for requests made to Spokes API.
    #
    # When set, this timeout will be used in place of Spokes API's internal default.
    attr_accessor :quality_of_service

    # Read after write.
    #
    # When set, Spokes API will assume that the request is trying to read data
    # that was just written. This is analagous to using a primary mysql, rather
    # than a read-only replica, in order to avoid replication lag.
    attr_accessor :read_after_write
  end

  # Temporarily set the 'read_after_write' flag to the specified val.
  def self.with_read_after_write(val)
    old, self.read_after_write = self.read_after_write, val
    begin
      yield
    ensure
      self.read_after_write = old
    end
  end

  # Temporarily override the quality of service for Spokes API calls.
  def self.with_quality_of_service(val)
    old, self.quality_of_service = self.quality_of_service, val
    begin
      yield
    ensure
      self.quality_of_service = old
    end
  end

  # Temporarily set Spokes API to fail fast if gitmon says to.
  def self.with_fail_fast
    with_quality_of_service(:QUALITY_OF_SERVICE_FAIL_FAST) do
      yield
    end
  end

  # SpokesAPI::NULL_OID is an alias for GitHub::NULL_OID so that the
  # deprecated reference is limited to this file.
  NULL_OID = ::GitHub::NULL_OID

  # Check if a given string is a valid 40 char SHA1.
  def self.valid_oid?(oid)
    # SpokesAPI::Util is private to this package, but this one method can be
    # public.
    SpokesAPI::Util.valid_oid?(oid)
  end

  class Error < StandardError
    def self.from_twirp_error(twirp_error)
      case twirp_error.code
      when :canceled
        return Canceled.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      when :deadline_exceeded
        return TimedOut.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      when :not_found
        return NotFound.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      when :invalid_argument
        return InvalidArgument.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      when :resource_exhausted
        return ResourceExhausted.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      end

      status = Twirp::ERROR_CODES_TO_HTTP_STATUS[twirp_error.code]
      case
      when status.nil?
        TwirpError.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      when status < 500
        TwirpClientError.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
      else
        if twirp_error.msg.include?("invalid connection")
          TwirpConnectionError.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
        else
          TwirpServerError.new(twirp_error.msg).tap { |err| err.twirp_error = twirp_error }
        end
      end
    end
  end

  class TwirpError < Error
    attr_accessor :twirp_error

    def failbot_context
      { twirp_error_code: twirp_error.code }
    end
  end

  class TwirpClientError < TwirpError; end
  class Canceled < TwirpClientError; end
  class InvalidArgument < TwirpClientError; end
  class NotFound < TwirpClientError; end
  class ResourceExhausted < TwirpClientError; end
  class TimedOut < TwirpClientError; end

  class TwirpServerError < TwirpError; end
  class TwirpConnectionError < TwirpError; end
end
