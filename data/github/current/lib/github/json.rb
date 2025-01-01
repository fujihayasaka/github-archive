# typed: true
# frozen_string_literal: true

require "yajl"

module GitHub
  # Abstract away which JSON library gets used on the various platforms we support
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

    # Adapted from the deletions in https://github.com/github/github/pull/362846/files
    # now that the standard JSON gem supports this functionality.
    def experimental_json_encode(obj, options = {})
      options = T.cast(Hash(options), T::Hash[Symbol, T.untyped])

      # Emulates YAJL's (frankly terrible) behaviour.
      # Unlike standard JSON we specifically avoid passing the state argument
      # to `to_json`, which confuses ActiveSupport, but achieves the result
      # GitHub has been using for a decade.
      coder = ::JSON::Coder.new(pretty: options[:pretty]) do |object|
        if object.respond_to?(:to_json)
          ::JSON::Fragment.new(object.to_json)
        else
          # Standard JSON falls back to to_s, but I'm not sure we ever reach
          # that. Everything responds to to_json.
          object.to_s
        end
      end

      # If the JSON has invalid UTF-8 characters, scrub them and re-process.
      # Avoid double-encoding by running the result through `::JSON.parse`
      # before re-`.to_json`ing in the coder.
      json = begin
        coder.dump(obj)
      rescue ::JSON::GeneratorError
        obj = scrub_invalid_utf8_hack(obj.to_json, obj: obj, options: options)
        coder.dump(::JSON.parse(obj))
      end

      recursively_process_strings(json)
    end

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
      failsafe = options.delete(:failsafe).present?
      options = Hash(options)

      Yajl::Parser.parse(str_or_io, options)
    rescue # rubocop:todo Lint/GenericRescue
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
      encode(canonicalize(obj), options)
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

    def recursively_process_strings(obj)
      case obj
      when String
        # \u001b and \u001B, for example, are both identical, so let's
        # upcase the hex digits for consistency between the behaviour of
        # YAJL and standard JSON encodings while preserving the case
        # of "\u".
        obj.gsub(/\\u([0-9a-f]{4})/i) { "\\u#{$1.upcase}" }
      when Array
        obj.map { |element| recursively_process_strings(element) }
      when Hash
        obj.transform_values { |value| recursively_process_strings(value) }
      else
        obj
      end
    end

    extend self
  end
end
