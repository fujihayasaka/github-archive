# typed: true
# frozen_string_literal: true

module GitHub
  module TokenScanning
    class FoundToken
      attr_reader :type, :token, :url, :report_url, :path, :processed, :error, :blob, :commit, :token_source
      attr_reader :start_line, :end_line, :start_column, :end_column
      attr_reader :content_type, :content_number, :content_id

      # Used to later report what was the last known state and last applied post processing for a found
      # token after the processors have run.
      attr_accessor :state, :post_processing

      # Initialize a new FoundToken instance.
      #
      # token_info  - A Hash of data about the found token.
      #               :type         - The String type of the token (Eg.
      #                               "GENERIC_SHA1").
      #               :token        - The String token that was found.
      #               :url          - A URL where the leaked token can be found.
      #               :report_url   - URL to report found token to.
      #               :blob         - The blob where the token was found
      #               :commit       - The commit where the token was found
      #               :path         - Path to the file
      #               :start_line   - Start line number
      #               :end_line     - End line number
      #               :start_column - Start column number
      #               :end_column   - End column number
      #
      # Returns nothing.
      def initialize(type:, token:, url:, report_url:, blob: nil, commit: nil,
                     path: nil, start_line: nil, end_line: nil,
                     start_column: nil, end_column: nil, token_source: nil,
                     content_type: nil, content_number: nil, content_id: nil)
        @type       = type
        @token      = token
        @url        = url
        @report_url = report_url
        @path       = path
        @blob       = blob
        @commit     = commit
        @token_source     = token_source

        @start_line = start_line || 0
        @end_line = end_line || 0
        @start_column = start_column || 0
        @end_column = end_column || 0

        @content_type = content_type
        @content_number = content_number
        @content_id = content_id

        @state = :unknown
        @processed = false
        @error = nil
        @post_processing = nil
      end

      def report_stats(stats_tags)
        GitHub.dogstats.increment("token_scan.token", tags: stats_tags + [
          "token_type:#{@type}",
          "result:#{@state}",
          "processed:#{@processed}",
          "error:#{@error || 'nil'}",
        ])
      end

      # Mark this token as processed. This will be used for reporting.
      def mark_processed
        @processed = true
      end

      # Mark this token as error state, and save the error name.
      # used for reporting later in the process.
      def error=(error)
        self.state = :error
        @error = error.class.name.underscore
      end

      def set_token_source(token_source)
        @token_source = token_source
      end

      def token_hash
        Digest::SHA256.hexdigest(token.to_s)
      end
    end
  end
end
