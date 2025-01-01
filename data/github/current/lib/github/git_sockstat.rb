# typed: true
# frozen_string_literal: true

module GitHub
  # GitSockstat is an opaque collection of strings that gets passed around
  # for various Git operations. Information about the request gets added to
  # it, and it eventually makes its way down to Git on the fileservers where
  # it ends up in ENV variables.
  #
  # The available variables are documented here:
  # https://thehub.github.com/engineering/development-and-ops/dotcom/git-sockstat/
  class GitSockstat
    UINTMAX_C = 2**64 - 1

    def self.decode(value, key: nil)
      case value
      when nil
      when /^bool:/
        value == "bool:true"
      when /^uint:/
        value.gsub(/^uint:/, "").to_i
      else
        value
      end
    end

    def self.encode(value, key: nil)
      case value
      when nil
      when String
        value.tr("\n\000", "")
      when true, false
        "bool:#{value}"
      when Integer
        if value < 0
          raise TypeError, "Unexpected negative stat value #{value}."
        end

        if value > UINTMAX_C
          raise TypeError, "Stat value #{key}=#{value} overflows C's UINTMAX_C value."
        end

        "uint:#{value}"
      else
        raise TypeError, "Unexpected stat value type for #{value}: #{value.class}"
      end
    end

    # Return a URL-form-encoded version of string s, but additionally,
    # encode spaces as `%20` rather than `+`. Encode `nil` to the
    # empty string. Note that this can be decoded back to the original
    # using `URI.decode_www_form_component()`:
    def self.url_escape(s)
      s = URI.encode_www_form_component(s || "")
      s.gsub!(/\+/, "%20")
      s
    end

    def self.format(stats)
      stats.map { |k, v| "stat=#{k}=#{encode(v, key: k)}" }
    end

    def self.parse(sockstats)
      vars = {}
      sockstats.each do |sockstat|
        k, v = sockstat.sub("stat=", "").split("=", 2)
        vars[k] = decode(v, key: k)
      end
      new vars
    end

    attr_reader :data
    alias_method :to_h, :data

    # The `data` is a hash, with keys that are either strings or symbols.
    # The values must be known acceptable git sockstat values:
    # nil, string, boolean, or non-negative integer.
    def initialize(data)
      @data = data

      @env = {}
      data.each do |k, v|
        @env["GIT_SOCKSTAT_VAR_#{k}"] = self.class.encode(v, key: k)
      end
      @env
    end

    def value(key)
      @data[key]
    end

    def remove(key)
      @data.delete(key)
    end

    def to_env
      @env
    end

    def register(actor)
      unless actor.respond_to?(:git_author_name) && actor.respond_to?(:git_author_email)
        return
      end

      unless @env.has_key? "GIT_COMMITTER_NAME"
        name = actor.git_author_name
        @env["GIT_COMMITTER_NAME"] = name

        # TODO: test using strings instead of symbols.
        @data[:committer_name] = name
      end

      unless @env.has_key? "GIT_COMMITTER_EMAIL"
        email = actor.git_author_email
        @env["GIT_COMMITTER_EMAIL"] = email

        # TODO: test using strings instead of symbols.
        @data[:committer_email] = email
      end
    end
  end
end
