# typed: true
# frozen_string_literal: true

# When sending data to third party service, we need to be mindful to not send data that is considered sensitive.
# What is considered sensitive?
# https://thehub.github.com/engineering/development-and-ops/observability/sentry/secure-exceptions/#identifying-your-sensitive-data
# goes into detail but at a high level, it's things that are Personally Identifiable Information (PII, like email
# address), Payment Card Industry data (PCI, like credit card numbers), and confidential data customers provide us
# (the name and contents of their private repositories).
#
# This was designed to be used for filtering exception data before being sent to Sentry, but can be used elsewhere.
#
# This module scrubs using two methods:
#
# - using regular expressions for data we can identify using them, like IP addresses and email addresse
# - using data that engineers flag as sensitive in their code
#
# To track sensitive data, use:
#
#     # track repository for the rest of the request
#     SensitiveData.context.push repo: repository.nwo
#
#     # track repository for the duration of the block
#     SensitiveData.context.push repo: repository.nwo do
#       # your code here
#     end
#
# SensitiveData.context accepts a few types:
#
# - String: the string that should be scrubed
# - Array: an area of strings, each is scrubed
#
# To actually scrub the data:
#
#     SensitiveData.scrub("potentially sensitive string")
#
# For how this ties into failbot and Sentry, see lib/github/config.rb's Failbot.before_report
module SensitiveData
  class << self
    attr_accessor :scrubber
  end

  def self.scrub(string, thread)
    scrubber.scrub(string, thread[:sensitive_data_context])
  end

  def self.coerce_to_string(input)
    scrubber.coerce_to_string(input)
  end

  def self.safe_input?(input)
    scrubber.safe_input?(input)
  end

  def self.context
    Thread.current[:sensitive_data_context] ||= Context.new
  end

  def self.context=(val)
    Thread.current[:sensitive_data_context] = val
  end

  def self.reset
    Thread.current[:sensitive_data_context] = nil
  end

  class Context < ::Context
    def push(hash = nil)
      if hash
        hash.each do |_key, value|
          case value
          when String, Array, nil
            # allowed
          else
            raise ArgumentError, "Unexpected value of type #{value.class} pushed: only String and Array allowed"
          end
        end
      end

      super
    end

    def scrub(string)
      to_hash.each do |key, value|
        # don't need to scrub nil
        next unless value

        # if empty string got on here, that would result in adding a bunch of [FILTERED] between each character
        next if value == ""

        case value
        when Array
          value.each do |v|
            string = scrub_value(string, key, v)
          end
        else
          string = scrub_value(string, key, value)
        end
      end

      string
    end

    def scrub_value(string, key, value)
      return string unless value
      value = value.to_s # coerce to a string if it's not already

      string.gsub(value) do |_match|
        "[FILTERED #{key.to_s.upcase}]"
      end
    end
  end

  REGULAR_EXPRESSIONS = {
    # This is copied from User::EMAIL_REGEX, with \A and \z removed
    email: /[^@\s.\0][^@\s\0]*@\[?[a-z0-9.-]+\]?/i,

    # This is the same regex we use in config/routes.rb
    ipv4: Regexp.new(Resolv::IPv4::Regex.to_s.gsub(/(?:\\A|\\z)/, "")),
    # TODO IPv6 is tricky because the regular expression is pretty loose. For example
    # :: is a valid IP for an empty octet, and that causes problems when we start talking about
    # Ruby classes, ie SlowQueryLogger::SlowQuery becomes SlowQueryLogger[FILTERED IP]SlowQuery
  }

  class Scrubber
    # List of safe values that won't be scrubbed. These will be checked with === so things like Class objects work
    # NOTE if you need to check github/github specific classes, might need to find another way to check it since not everything is always going to be loaded
    # see how lib/github/config/failbot.rb's exception_is_a? as an example
    SAFE_INPUTS = [
      # a class name isn't going to be sensitive
      Class,

      # these would be no-op
      nil,
      "",

      # these types get coerced to string in Failbot#sanitize, so we don't need to scrub them
      true,
      false,
      Time,
      Date,
      Numeric,
    ]

    def scrub(string, context)
      return string if safe_input?(string)

      # match what Failbot#sanitize does for other types
      string = string.inspect unless string.kind_of?(String)

      REGULAR_EXPRESSIONS.each do |key, regexp|
        if regexp.match?(string)
          string = string.gsub(regexp, "[FILTERED #{key.to_s.upcase}]")
        end
      end

      string = context.scrub(string)
    end

    def coerce_to_string(string)
      return string if string.kind_of?(String)
      string.inspect
    end

    def safe_input?(input)
      SAFE_INPUTS.any? { |safe_input| safe_input === input } # rubocop:disable Style/CaseEquality
    end
  end

  self.scrubber = Scrubber.new
end
