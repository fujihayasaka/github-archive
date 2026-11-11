# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    class Page
      class CacheKey < T::Struct
        const :base, String, default: "site.swp"
        const :locale, String, default: "en"
        const :path, String
        const :user_provided_parameters, T::Hash[Symbol, String], default: {}
        const :version, Integer, default: 0
        const :preview, T::Boolean, default: false

        # Disallowed URL path characters
        DISALLOWED_PATH_CHARACTERS = T.let(/[^a-zA-Z0-9\-\/_]/, Regexp)
        MAX_KEY_LENGTH = Site::KV::MAX_KEY_LENGTH
        DIGEST_LENGTH = 32

        sig { returns(String) }
        def to_s
          if length <= MAX_KEY_LENGTH
            "#{human_readable_base}.#{digest}"
          else
            "truncated_key.#{full_digest}"
          end
        end

        private

        sig { returns(T::Array[String]) }
        def segments
          [
            base,
            locale,
            normalized_path,
            preview ? "preview" : "",
            "v#{version}",
          ].reject { |segment| segment.empty? }
        end

        sig { returns(String) }
        def sanitized_path
          path.gsub(DISALLOWED_PATH_CHARACTERS, "") # remove disallowed characters
        end

        sig { returns(String) }
        def normalized_path
          sanitized_path
            .gsub("/", "_") # replace slashes with underscores
            .gsub(/\A_+|_+\z/, "") # remove leading/trailing underscores
        end

        sig { returns(String) }
        def digest
          "#{full_digest[0, DIGEST_LENGTH]}"
        end

        sig { returns(String) }
        def full_digest
          base = human_readable_base
          # Add sanitized path to avoid collisions for paths that normalize to the same value
          base += "#{sanitized_path}"
          # Add user-provided parameters (in sorted order) to avoid collisions for the same path with different params
          base += "#{user_provided_parameters.to_param}"

          Digest::SHA256.hexdigest(base)
        end

        sig { returns(String) }
        def human_readable_base
          segments.join(".")
        end

        sig { returns(Integer) }
        def length
          # +1 for the dot between human-readable key and digest
          human_readable_base.length + 1 + DIGEST_LENGTH
        end
      end
    end
  end
end
