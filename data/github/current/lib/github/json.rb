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

    def rapidjson_encode(obj, options = {})
      options = T.cast(Hash(options), T::Hash[Symbol, T.untyped])

      # A coder which emulates YAJL's (frankly terrible) behaviour
      # Unlike standard JSON we specifically avoid passing the state argument
      # to `to_json`, which confuses Active Support, but achieves the result
      # GitHub has been using for a decade.
      coder = RapidJSON::Coder.new(pretty: options[:pretty]) do |object, is_key|
        if is_key
          object.to_s
        else
          if object.respond_to?(:to_json)
            RapidJSON::Fragment.new(object.to_json)
          else
            # standard JSON falls back to to_s, but I'm not sure we ever reach
            # that. Everything responds to to_json
            object
          end
        end
      end
      json = coder.dump(obj)

      scrub_invalid_utf8_hack(json, obj:, options:)

      json
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
      options = Hash(options)

      Yajl::Parser.parse(str_or_io, options)
    rescue # rubocop:todo Lint/GenericRescue
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

    extend self
  end

  module FailsafeJSON
    def load(value)
      GitHub::JSON.load(value)
    rescue Yajl::ParseError
      GitHub.dogstats.increment("session_serialization", tags: ["action:load", "error:invalid_json"])
      nil
    end

    def dump(value)
      GitHub::JSON.dump(value)
    end

    extend self
  end
end
