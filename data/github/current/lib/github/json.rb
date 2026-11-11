# typed: true
# frozen_string_literal: true

require "yajl"

module GitHub
  # Why do we use YAJL as our JSON library? Once upon a time, it was faster than the built-in Ruby JSON.
  #
  # We attempted to do a migration from YAJL to Ruby JSON because the latter is just as fast and better in other ways.
  # Ultimately, in May 2025, we're sticking with YAJL because the migration is a huge, complex, and risky job that
  # involves many teams.
  #
  # We tried various Science experiments to make sure that YAJL and JSON behaved consistently, with mixed success.
  # The way YAJL encodes JSON is different from Ruby JSON in that YAJL will accept anything we throw at it (there's a
  # method in this file whose name ends with the word "hack").
  #
  # GitHub relies on JSON the format extremely heavily. It's used _everywhere_, we do not have 100% test coverage to
  # be truly confident in not breaking anything, and if we do break the mechanics of API requests, for example, or
  # the current behaviour that binary data and emoji are allowed in branch names, it's _very_ visible to users.
  #
  # Read https://github.com/github/ruby-architecture/issues/416 to learn more. :-)
  module JSON
    autoload :CachedFetchRemoteUrl, "github/json/cached_fetch_remote_url"
    autoload :ArbitraryDocument, "github/json/arbitrary_document"
    include Kernel

    class InvalidEncoding < StandardError
    end

    # ActiveSupport::JSON expects this to be defined on all JSON backends.
    ParseError = Yajl::ParseError

    mattr_accessor :warn_utf8_sample_rate, default: GitHub::AppEnvironment.test? ? 0 : 0.1

    def encode(obj, options = {})
      options = T.cast(Hash(options), T::Hash[Symbol, T.untyped])
      json = Yajl::Encoder.encode(obj, options)
      json.force_encoding("UTF-8")

      scrub_invalid_utf8_hack(json, obj:, options:)

      json
    end
    alias_method :dump,  :encode
    alias_method :yajl_encode, :encode
    alias_method :yajl_dump, :encode

    def scrub_invalid_utf8_hack(json, obj:, options:)
      if !json.valid_encoding?
        json.scrub!

        GitHub.dogstats.increment("github.encoding.json_encode_invalid_utf8")

        if options[:warn_utf8] || rand < warn_utf8_sample_rate
          error = InvalidEncoding.new("Encoded JSON object with invalid UTF8 bytes")
          error.set_backtrace(caller)
          GitHub::Logger.log_exception({
            class: error.class.name,
            json_object: (obj.inspect unless options[:dangerously_allow_all_keys]),
            json_options: options.inspect,
          }, error)
          # raise the error without information from the JSON itself
          # more information can be found in splunk
          Failbot.report_user_error(error)
        end
      end
      json
    end

    def decode(str_or_io, options = {})
      failsafe = options.fetch(:failsafe, nil).present?
      options = Hash(options)

      Yajl::Parser.parse(str_or_io, options)
    rescue # rubocop:todo Lint/RescueException
      return nil if failsafe # We don't care about the error in failsafe mode.

      if !options[:retried] && $!.to_s =~ /utf/i && str_or_io.respond_to?(:scrub)
        options[:retried] = true
        str_or_io = str_or_io.scrub
        retry
      else
        raise
      end
    end
    alias_method :parse, :decode
    alias_method :load,  :decode

    # Dump an object to JSON such that its string is stable across equivalent
    # objects by recursively sorting keys.
    def canonical_encode(obj, options = {})
      canonicalized_obj = canonicalize(obj)

      yajl_encode(canonicalized_obj, options)
    end

    # Duplicate a JSON-compatible object while sorting all hash keys.
    # Matches the behavior of relay's stableCopy.
    def canonicalize(obj)
      if obj.instance_of?(Array)
        obj.map { |x| canonicalize(x) }
      elsif obj.instance_of?(Hash)
        obj.sort.each_with_object({}) do |(k, v), dupe|
          dupe[k] = canonicalize(v)
        end
      else
        obj
      end
    end

    extend self
  end
end
