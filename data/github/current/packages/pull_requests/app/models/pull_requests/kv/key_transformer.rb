# typed: true
# frozen_string_literal: true

require "github/config/kv_dual_write"

module PullRequests
  module KV
    class KeyTransformer
      include GitHub::Config::DualWriteKV::IKeyTransformer

      class UnexpectedKeyFormat < ArgumentError; end

      sig { params(old_key_pattern: Regexp, new_key_template: String).void }
      def initialize(old_key_pattern:, new_key_template:)
        string_pattern = old_key_pattern.to_s
        unless string_pattern.include?("\\A") && string_pattern.include?("\\z")
          raise(ArgumentError,
            "`old_key_pattern` must match the whole string, i.e. "\
            "it must start with `\\A` and end with `\\z`.\n\n"\
            "Pattern was: #{string_pattern}"
          )
        end

        unless old_key_pattern.names.include?("repository_id")
          raise(ArgumentError,
            "`old_key_pattern` must have a named capture called `repository_id`, "\
            "i.e. the regexp must contain `(?<repository_id>\d+)`"
          )
        end

        template_vars = new_key_template.scan(/%\{([a-z_]+)\}/).flatten
        bad_template_vars = template_vars - old_key_pattern.names
        if bad_template_vars.any?
          raise(ArgumentError,
            "`new_key_template` cannot contain template variables that don't "\
            "correspond to named captures in `old_key_pattern`, e.g. "\
            "if `new_key_template` is 'prs/foo/%{user_id}', then "\
            "`old_key_pattern` must contain something like `(?<user_id>\d+)`.\n\n"\
            "Unexpected template variables were: #{bad_template_vars.join(", ")}.\n"\
            "Old key named captures were: #{old_key_pattern.names.join(", ")}.\n"
          )
        end

        @old_key_pattern = old_key_pattern
        @new_key_template = new_key_template
      end

      sig { override.params(key: String).returns(String) }
      def transform(key)
        new_key, _ = new_key_and_repo_id(key)
        new_key
      rescue UnexpectedKeyFormat
        key
      end

      sig { override.params(prefix: String).returns(String) }
      def transform_prefix(prefix)
        raise NotImplementedError, "Prefix operations are not supported by this key transformer"
      end

      sig { params(old_key: String).returns([String, Integer]) }
      def new_key_and_repo_id(old_key)
        if match = old_key.match(@old_key_pattern)
          [@new_key_template % match.named_captures.symbolize_keys, match[:repository_id].to_i]
        else
          raise UnexpectedKeyFormat, "Unexpected key format: #{old_key}"
        end
      end
    end
  end
end
