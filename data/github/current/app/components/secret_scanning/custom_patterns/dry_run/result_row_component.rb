# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class ResultRowComponent < ApplicationComponent
        include DiffHelper
        include GitHub::TokenScanning::SecretScanningHelper
        include SecretScanningCustomPatternsHelper
        include UrlHelper

        attr_reader :result, :repo, :pattern_scope

        def initialize(result:, repo:, pattern_scope:)
          @result = result
          @repo = repo
          @pattern_scope = pattern_scope
        end

        memoize def token_literal
          location_blobs = fetch_blobs(@repo, [first_location])

          raw_secret = SecretScanning::Util::RawSecret.get_raw_secret_from_location(
            first_location,
            @repo,
            location_blobs,
            nil, # alert is nil since dry run results don't have alerts
            @result.custom_pattern_id,
            true # is_dry_run
          )

          SecretScanning::Util::RawSecret.token_literal_from_secret(raw_secret)
        end

        def truncated_raw_secret
          return "No preview" if token_literal.nil?
          token_literal.truncate(SecretScanningCustomPatternsHelper::DRY_RUN_RESULT_TRUNCATION_LENGTH)
        end

        def file_path
          path_string = reverse_truncate(first_location.path, length: SecretScanningCustomPatternsHelper::DRY_RUN_RESULT_TRUNCATION_LENGTH)
          start_line = first_location.start_line || 0
          "%s:%d" % [path_string, start_line]
        end

        def secret_url
          anchor = "L#{first_location.start_line}-L#{first_location.end_line}"
          "#{blob_view_url(first_location.path, first_location.commit_oid, @repo)}##{anchor}"
        end

        def first_location
          @result.locations.first
        end
      end
    end
  end
end
