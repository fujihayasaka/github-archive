# typed: true
# frozen_string_literal: true

require "faraday"
require "json"
require "set"
require "uri"
require "base64"
require "zstd-ruby"

require_relative "azure_client"
require_relative "github_client"
require_relative "diff_parser"

module GitHub
  module QueryGuard
    class PullRequestCommenter
      COUNT_STAR_INDEX_THRESHOLD = 100
      LIMIT_MESSAGE = <<~TEXT
        Query Guard has detected you've introduced a new query that does not use a `LIMIT` clause. This is a potential performance risk, as queries without limits can return large result sets, leading to increased load on the database and application.

        If possible, please consider adding a `LIMIT` clause to your query to restrict the number of rows returned. This helps ensure that the query performs efficiently and does not impact the overall performance of the application.
        If you believe that this query is safe and necessary without a `LIMIT`, please respond to this comment with a 👍 to acknowledge the risk.
        </br>
      TEXT
      INDEX_MESSAGE = <<~TEXT
        Query Guard has detected you've introduced a new query that may not use an index. This is a potential performance risk, as queries without indexes can lead to full table scans, resulting in slower query execution times and increased load on the database.

        If possible, please consider optimizing your query to use an index. This can significantly improve the performance of the query and reduce the load on the database.
        If you believe that this query is safe and necessary without an index, please respond to this comment with a 👍 to acknowledge the risk.
        </br>
      TEXT

      class BacktraceFrame < T::Struct
        const :file, String
        const :label, T.nilable(String)
        const :line, Integer

        sig { params(frame_data: T.untyped).returns(T.nilable(BacktraceFrame)) }
        def self.from(frame_data)
          return nil unless frame_data.is_a?(Array) && frame_data.length >= 3
          file, label, line = frame_data[0], frame_data[1], frame_data[2]

          return nil unless file.is_a?(String)

          line_num = T.let(Integer(line, exception: false), T.nilable(Integer))
          return nil unless line_num && line_num.positive?

          label = label.is_a?(String) ? label : nil
          new(file: file, label: label, line: line_num)
        end

        sig { returns(String) }
        def to_s
          return "#{file}:#{line}" if label.nil?

          "#{file}:#{line} in `#{label}`"
        end
      end

      class BackTrace
        sig { params(frames: T::Array[BacktraceFrame]).void }
        def initialize(frames)
          @frames = frames
        end

        sig { returns(T::Array[BacktraceFrame]) }
        attr_reader :frames

        sig { params(backtrace_data: T.nilable(T::Array[T::Array[T.untyped]])).returns(T.nilable(BackTrace)) }
        def self.from(backtrace_data)
          return nil unless backtrace_data.is_a?(Array)

          frames = backtrace_data.filter_map { |frame_data| BacktraceFrame.from(frame_data) }
          return nil if frames.empty?

          new(frames)
        end

        sig { returns(String) }
        def to_s
          @frames.map(&:to_s).join("\n")
        end
      end

      class RerunQueryResult < T::Struct
        const :digest, String
        const :digest_text, String
        const :query_sample_text, String
        const :backtrace, T.nilable(BackTrace)
        const :sum_no_index_used, Integer
        const :count_star, Integer
      end

      attr_reader :repo, :pr_number, :original_run_id, :rerun_run_id

      sig do
        params(
          repo: String,
          pr_number: T.nilable(String),
          branch_name: String,
          head_sha: String,
          event_name: String,
          original_run_id: String,
          rerun_run_id: String,
          should_comment: T::Boolean,
          github_client: GitHub::QueryGuard::GitHubClient,
          kusto_client: GitHub::QueryGuard::Azure::Kusto,
          event_hub_client: GitHub::QueryGuard::Azure::EventHub
        ).void
      end
      def initialize(repo, pr_number, branch_name, head_sha, event_name, original_run_id, rerun_run_id, should_comment, github_client, kusto_client, event_hub_client)
        @repo = repo
        @pr_number = pr_number
        @branch_name = branch_name
        @head_sha = head_sha
        @event_name = event_name
        @original_run_id = original_run_id
        @rerun_run_id = rerun_run_id
        @should_comment = should_comment

        @github_client = github_client
        @kusto_client = kusto_client
        @event_hub_client = event_hub_client
      end

      def run
        puts "Starting Query Guard for repo: #{@repo}, pr_number: #{@pr_number}, branch_name: #{@branch_name}, event_name: #{@event_name}, original_run_id: #{@original_run_id}, rerun_run_id: #{@rerun_run_id}"

        queries = query_digests
        return if queries.empty?

        # Get PR diff and correlate with backtraces
        pr_diff = @github_client.get_diff(@repo, T.must(@pr_number)).body

        correlated_digests = correlate_backtraces_with_diff(queries, pr_diff)
        return if correlated_digests.empty?

        existing_comments = existing_comment_query_digests
        filtered_digests = filter_relevant_digests(correlated_digests, existing_comments)
        return if filtered_digests.empty?

        post_review_comments(filtered_digests, existing_comments)
        ingest_posted_query_digests(filtered_digests.keys)
      end

      sig { params(correlated_digests: T::Hash[String, [BacktraceFrame, RerunQueryResult, BackTrace]], existing_comments: T::Set[String]).returns(T::Hash[String, [BacktraceFrame, RerunQueryResult, BackTrace]]) }
      def filter_relevant_digests(correlated_digests, existing_comments)
        correlated_digests.select do |digest, (frame, _query, backtrace)|
          next false if existing_comments.include?(digest)

          unless relevant_backtrace?(frame, backtrace)
            puts "Skipping digest #{digest}: no relevant backtrace found."
            next false
          end

          true
        end
      end

      sig { params(correlated_digests: T::Hash[String, [BacktraceFrame, RerunQueryResult, BackTrace]], existing_comments: T::Set[String]).void }
      def post_review_comments(correlated_digests, existing_comments)
        comments = []
        groups = Hash.new { |h, k| h[k] = [] }

        correlated_digests.each do |digest, (frame, query, backtrace)|
          uses_index = !(query.sum_no_index_used > 0 && query.count_star > COUNT_STAR_INDEX_THRESHOLD)
          has_limit = query.digest_text.match?(/\s+limit\s+(?:\d+|\?)/i)

          content_sections = []
          content_sections << LIMIT_MESSAGE unless has_limit
          content_sections << INDEX_MESSAGE unless uses_index

          risk_details = if content_sections.any?
            <<~DETAILS
              <details>
                <summary><strong>Risks identified</strong></summary>

                #{content_sections.join("\n\n")}
              </details>
            DETAILS
          else
            ""
          end

          sql = format_query(query.query_sample_text) rescue query.query_sample_text

          body = <<~TEXT
            <!-- query_guard:digest_hash:#{digest} -->

            ### 🧙‍♂️🛡️ Detected New Query:
            **Digest**: `#{digest}`

            ```sql
            #{sql}
            ```

            <details>
              <summary><strong>Backtrace</strong></summary>
            <p>

            ```ruby
            #{backtrace}
            ```

            </p>
            </details>

            #{risk_details}
          TEXT

          groups[[frame.file, frame.line]] << body
        end

        groups.each do |(file, line), bodies|
          if bodies.size == 1
            comments << {
              "path" => file,
              "line" => line,
              "side" => "RIGHT",
              "body" => bodies.first
            }
          else
            first_body = bodies.shift
            rest_count = bodies.size
            rest_bodies = bodies.join("\n\n---\n\n")
            combined_body = <<~TEXT
              #{first_body}

              ---

              <details>
                <summary><strong>Found #{rest_count} more #{rest_count == 1 ? "Query" : "Queries"}</strong></summary>

              #{rest_bodies}
              </details>
            TEXT

            comments << {
              "path" => file,
              "line" => line,
              "side" => "RIGHT",
              "body" => combined_body
            }
          end
        end

        return if comments.empty?

        message = <<~TEXT
          ## Query Guard 🧙‍♂️🛡️ has detected new queries

          To ensure new queries are safe and performant in production, please [`EXPLAIN` your query](https://thehub.github.com/epd/engineering/dev-practicals/mysql/running-explain-against-production) and validate that it has the [proper indexes](https://thehub.github.com/epd/engineering/dev-practicals/mysql/optimizing-indexes/) before shipping to production. Please share the `EXPLAIN` in this PR for the owners of this data store and code reviewers.

          <details>
            <summary><strong>What is Query Guard?</strong></summary>

            Query Guard is a tool designed to track and surface new MySQL queries introduced in this pull request. This helps ensure that database performance and query behavior are well-understood before changes are merged.

            We value your feedback! If you have any questions, concerns, or suggestions about Query Guard, feel free to reach out in [#pre-prod-query-tooling](https://github-grid.enterprise.slack.com/archives/C06Q814V2BX).
          </details>
        TEXT
        message = "" unless existing_comments.empty?

        if @should_comment
          @github_client.create_review(@repo, T.must(@pr_number), T.must(@head_sha), message, "COMMENT", comments)
        end

        puts "Posting comments to PR:"
        puts comments.to_json
      end

      def format_query(sql)
        require "anbt-sql-formatter/formatter"

        # trim the query comments
        sql = sql.gsub(%r{/\*.*?\*/}m, "").strip

        # format the sql
        rule = AnbtSql::Rule.new
        rule.keyword = AnbtSql::Rule::KEYWORD_UPPER_CASE
        rule.space_after_comma = true
        rule.indent_string = "  "

        AnbtSql::Formatter.new(rule).format(sql.dup)
      rescue LoadError
        sql
      end

      sig { params(digests: T::Array[String]).void }
      def ingest_posted_query_digests(digests)
        payload = digests.map do |digest|
          {
            query: {
              digest: digest,
            },
            metadata: {
              branch_name: @branch_name,
              github_run_id: @original_run_id,
              pr_number: @pr_number,
            },
            timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%NZ"),
          }
        end

        return if payload.empty?

        @event_hub_client.ingest(messages: payload, table: "ci_query_comments")
      end

      sig { params(queries: T::Array[RerunQueryResult], pr_diff: String).returns(T::Hash[String, [BacktraceFrame, RerunQueryResult, BackTrace]]) }
      def correlate_backtraces_with_diff(queries, pr_diff)
        parser = GitHub::QueryGuard::DiffParser.new(pr_diff)

        queries.each_with_object({}) do |query_result, matches|
          backtrace = query_result.backtrace
          next if backtrace.nil?

          matching_frame = backtrace.frames.find { |frame| parser.includes_line?(frame.file, frame.line) }

          if matching_frame
            matches[query_result.digest] = [matching_frame, query_result, backtrace]
          else
            puts "No diff match for digest: #{query_result.digest}"
          end
        end
      end

      sig { returns(T::Array[RerunQueryResult]) }
      def query_digests
        query_text = <<~QUERY
          ci_query_diff_results
          | where run_id == #{@original_run_id}
          | distinct digest, digest_text
          | join kind=inner (
              ci_stmt_summary_rerun
              | where run_id ==  #{@rerun_run_id}
              | project digest, query_sample_text, backtrace, sum_no_index_used, count_star
          ) on digest
          | summarize take_any(digest_text), take_any(query_sample_text), take_any(backtrace), sum_no_index_used = sum(sum_no_index_used), count_star = sum(count_star) by digest
          | project digest, digest_text, query_sample_text, backtrace, sum_no_index_used, count_star
        QUERY

        @kusto_client.query(query_text, "Queries").map do |row|
          digest, digest_text, query_sample_text, backtrace, sum_no_index_used, count_star = row
          decoded_backtrace = decode_backtrace(backtrace)
          RerunQueryResult.new(
            digest: digest,
            digest_text: digest_text,
            query_sample_text: query_sample_text,
            backtrace: decoded_backtrace,
            sum_no_index_used: sum_no_index_used.to_i,
            count_star: count_star.to_i
          )
        end
      end

      sig { returns(Set) }
      def existing_comment_query_digests
        query_text = <<~QUERY
          ci_query_comments
            | where pr_number == "#{pr_number}"
            | project digest
        QUERY

        @kusto_client.query(query_text, "Queries").map { |row| row.first }.to_set
      end

      sig { params(backtrace: T.nilable(String)).returns(T.nilable(BackTrace)) }
      def decode_backtrace(backtrace)
        return nil if backtrace.nil? || backtrace.empty?

        begin
          compressed = Base64.strict_decode64(backtrace)
          json = Zstd.decompress(compressed)
          parsed = JSON.parse(json)
          return if parsed.nil?

          BackTrace.from(parsed)
        rescue StandardError => e
          puts "Failed to decode backtrace: #{e.message}"
          nil
        end
      end

      sig { params(file_path: String).returns(T::Boolean) }
      def is_app_file?(file_path)
        file_path.match?(%r{\A(?:app|packages/[^/]+/app)(?:/|$)})
      end

      sig { params(frame: BacktraceFrame, backtrace: BackTrace).returns(T::Boolean) }
      def relevant_backtrace?(frame, backtrace)
        true if is_app_file?(frame.file)

        backtrace.frames.any? do |f|
          is_app_file?(f.file)
        end
      end
    end
  end
end
