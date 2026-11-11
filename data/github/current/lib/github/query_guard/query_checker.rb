# typed: true
# frozen_string_literal: true

require "faraday"
require "json"
require "set"
require "uri"

require_relative "azure_client"
require_relative "github_client"

module GitHub
  module QueryGuard

    class QueryChecker

      class QueryDiffResult < T::Struct
        const :digest, String
        const :digest_text, String
        const :test_name, T.nilable(String)
        const :merge_queue_branches, T.nilable(T::Array[String])
      end

      attr_reader :repo, :pr_number, :run_id

      sig do
        params(
          repo: String,
          pr_number: T.nilable(String),
          branch_name: String,
          event_name: String,
          run_id: String,
          github_client: GitHub::QueryGuard::GitHubClient,
          kusto_client: GitHub::QueryGuard::Azure::Kusto,
          event_hub_client: GitHub::QueryGuard::Azure::EventHub
        ).void
      end
      def initialize(repo, pr_number, branch_name, event_name, run_id, github_client, kusto_client, event_hub_client)
        @repo = repo
        @pr_number = pr_number
        @branch_name = branch_name
        @event_name = event_name
        @run_id = run_id

        @github_client = github_client
        @kusto_client = kusto_client
        @event_hub_client = event_hub_client
      end

      def run
        puts "Starting Query Guard for repo: #{@repo}, pr_number: #{@pr_number}, branch_name: #{@branch_name}, event_name: #{@event_name}, run_id: #{@run_id}"
        queries = query_diffs

        existing_digests = existing_comment_query_digests
        queries = queries.reject do |query|
          existing_digests.include?(query.digest) ||
          digests_merged(query.merge_queue_branches)
        end

        should_score = !(queries.empty? || @event_name == "merge_group")
        confidence = should_score ? score_confidence(queries) : {}

        high_confidence, low_confidence = if confidence.empty?
          [queries, []]
        else
          queries.partition { |query| confidence.fetch(query.digest, -1) >= 0.5 }
        end

        ingest_diffs(queries, confidence)

        if high_confidence.empty?
          puts "No new queries found"
        end

        if low_confidence.any?
          puts "Low confidence queries: #{low_confidence.map(&:digest).join(', ')}"
        end

        write_tests_file(high_confidence) if high_confidence.any?
      end

      sig { params(merge_queue_branches: T.nilable(T::Array[String])).returns(T::Boolean) }
      def digests_merged(merge_queue_branches)
        return false if merge_queue_branches.nil? || merge_queue_branches.empty?

        @sha_status ||= {}

        merge_queue_branches.each do |branch|
          sha = branch.split("-").last || ""
          return false if sha.empty? || sha.length != 40

          status = @sha_status[sha] ||= begin
            response = @github_client.get_commit_compare(@repo, "master", sha)
            response.body["status"]
          end

          return true if %w[identical behind].include?(status)
        end
        false
      end

      sig { returns(T::Array[QueryDiffResult]) }
      def query_diffs
        query_text = <<~QUERY
          let inputRunId = #{run_id};

          let recentRunIds = stmt_summary
            | where branch == "master" and run_id != inputRunId
            | summarize by run_id
            | top 250 by run_id desc;

          let recentDigests = stmt_summary
            | where run_id in (recentRunIds)
            | summarize by digest;

          let newDigests = stmt_summary
            | where run_id == inputRunId
            | summarize digest_text = take_any(digest_text), test_name = take_any(test_name) by digest
            | where digest !in (recentDigests)
            | project digest, digest_text, test_name
            | order by digest asc
            | limit 50;

          let latestMergeQueues = stmt_summary
            | where branch startswith_cs "refs/gh/queue/" and digest in (newDigests)
            | where timestamp > ago(14d)
            | limit 10
            | sort by timestamp asc
            | project digest, branch
            | summarize merge_queue_branches = make_list(branch) by digest;

          newDigests
          | join kind=leftouter latestMergeQueues on digest
          | project digest, digest_text, test_name, merge_queue_branches
        QUERY

        @kusto_client.query(query_text, "Queries").map do |row|
          QueryDiffResult.new(
            digest: row[0],
            digest_text: row[1],
            test_name: row[2],
            merge_queue_branches: row[3]
          )
        end
      end

      sig { params(queries: T::Array[QueryDiffResult], confidence: T::Hash[String, Float]).void }
      def ingest_diffs(queries, confidence)
        diffs = queries.empty? ? [QueryDiffResult.new(digest: "", digest_text: "", test_name: nil, merge_queue_branches: nil)] : queries
        diffs = diffs.map do |query|
          {
            query: {
              digest: query.digest,
              digest_text: query.digest_text,
              score: confidence[query.digest] || -1,
            },
            metadata: {
              branch_name: @branch_name,
              github_run_id: @run_id,
            },
            timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%NZ")
          }
        end

        @event_hub_client.ingest(messages: diffs, table: "ci_query_diff_results")
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

      sig { params(queries: String, pr_diff: String).returns(String) }
      def score_confidence_prompt(queries, pr_diff)
        <<~TEXT
          You are Query-Guard, a specialized AI sql tool. Your purpose is to determine if specific SQL queries are likely to have been introduced or their execution paths affected by changes in a given Pull Request (PR) diff. You will assess this for Continuous Integration (CI) run verification.

          You will receive:
          1.  A list of SQL queries. Each query has a `digest` (a unique identifier) and the `query` string itself.
          2.  An associated PR `diff` showing the code changes.

          Your Task:
          For each SQL query provided in the list:
          1.  **Analyze**: Carefully examine the SQL query (paying attention to tables, columns, and operations) and the entire PR diff (including application code changes, test code changes, schema migrations, feature flag modifications, etc.).
          2.  **Correlate**: Identify any new or modified code in the PR diff that could:
              * Directly generate or execute the SQL query (e.g., new Object-Relational Mapper (ORM) calls, raw SQL strings, changes to stored procedures invoked by the application).
              * Indirectly lead to the execution of the SQL query (e.g., changes in business logic, controller actions, service methods, or background jobs that use models or data related to the query).
              * Be tested by new or modified tests that would execute the SQL query.
          3.  **Considerations for Correlation**:
              * **Table and Column Names**: Does the PR diff interact with the tables or columns mentioned in the SQL query?
              * **Domain Concepts & Model Relationships**: Does the PR diff touch parts of the application (models, services, controllers) that deal with the data or domain concepts involved in the query?
              * **Verbatim Match Not Required**: The SQL query does not need to appear verbatim in the code. Focus on the *effect* of the code changes. ORM operations, changes in data access patterns, or modified business logic can all be relevant.
              * **Feature Flags**: Are there any new or modified feature flags in the diff that could enable code paths leading to this query's execution?
              * **Version Updates**: If the PR diff includes version updates (e.g., gems, libraries), consider if these changes could affect the SQL query's execution. Important: in that case mark all  queries as 0.7.
          4.  **Score**: Assign a confidence score between 0.0 (no evidence of relation or extremely unlikely) and 1.0 (strong evidence of relation or highly likely) that the PR diff's changes are responsible for introducing this specific SQL query or altering its execution circumstances.

          **Input Data:**

          SQL Queries in `<digest>: <query>` format
          ```
          #{queries}
          ```

          Associated PR Diff:
          ```diff
          #{pr_diff}
          ```

          **Output Requirements:**
          * Provide one line of output per SQL query from the input list.
          * Each line *must* strictly contain the query's `digest`, followed by a comma and a space, followed by its confidence `score` (e.g., `0.75`).
          * **Respond ONLY with these lines.** Do not include any introductory text, explanations, reasoning, headers, or summaries in your response. Adhere strictly to the line-by-line format.

          Example output if three queries were provided:
          `digest_of_query_1, 0.95`
          `digest_of_query_2, 0.10`
          `digest_of_query_3, 0.0`

          Begin your analysis based on the actual queries and PR diff provided.
        TEXT
      end

      sig { params(query_result: T::Array[QueryDiffResult]).returns(T::Hash[String, Float]) }
      def score_confidence(query_result)
        queries = query_result.map { |query| "#{query.digest}: #{query.digest_text}" }.join("\n")
        pr_diff_raw = @github_client.get_diff(@repo, T.must(@pr_number)).body

        pr_diff = truncated_pr_diff(pr_diff_raw, queries)

        begin
          prompt = score_confidence_prompt(queries, pr_diff)
          body = @github_client.infer(prompt, "openai/gpt-5-chat").body
          puts "llm response: #{body}"

          if body.dig("error", "code") == "RateLimitReached"
            puts "Rate limit reached for primary model"
            body = @github_client.infer(prompt, "openai/gpt-5-mini").body
            puts "llm response: #{body}"
          end

          response = body.dig("choices", 0, "message", "content")&.strip
          return {} unless response

          confidence = response.split("\n").each_with_object({}) do |line, map|
            digest, score = line.match(/^`?(.*?)`?,\s*([\d.]+)$/)&.captures
            map[digest] = score.to_f if digest && score
          end

          puts "Confidence scores: #{confidence}"
          confidence
        rescue StandardError => e
          puts "Error during LLM inference: #{e.message}"
          {}
        end
      end

      private

      sig { params(pr_diff_raw: String, queries: String).returns(String) }
      def truncated_pr_diff(pr_diff_raw, queries)
        max_token = 15000
        prompt_token = token_estimate(score_confidence_prompt("", ""))
        queries_token = token_estimate(queries)
        pr_diff_token = token_estimate(pr_diff_raw)
        total_estimated_token = prompt_token + queries_token + pr_diff_token

        return pr_diff_raw if total_estimated_token <= max_token

        pr_diff = compact_diff(pr_diff_raw)
        pr_diff_token = token_estimate(pr_diff)
        total_estimated_token = prompt_token + queries_token + pr_diff_token

        # if still too large, truncate
        if total_estimated_token > max_token
          remaining_token = (max_token - prompt_token - queries_token) * 4
          pr_diff = pr_diff.slice(0, remaining_token) || ""
        end

        puts "Truncated PR diff to fit token limit. Original tokens: #{total_estimated_token}"
        pr_diff
      end

      sig { params(text: String).returns(Integer) }
      def token_estimate(text)
        (text.length / 4.0).ceil
      end

      sig { params(diff: String).returns(String) }
      def compact_diff(diff)
        sections = diff.split(/^diff --git/)

        filtered_sections = sections.map do |section|
          filename = section[/\+\+\+ b\/([^\n]+)/, 1]
          changed_lines = section.lines.grep(/^[-+]/)
            .reject { |line| line.start_with?("+++", "---") }

          filename && changed_lines.any? ? ([filename] + changed_lines).join : nil
        end

        filtered_sections.compact.join
      end

      sig { params(queries: T::Array[QueryDiffResult]).void }
      def write_tests_file(queries)
        test_names = queries.map(&:test_name).compact
        with_location, without_location = test_names.partition { |n| n.match?(/^.+:::/) }

        # Convert L<number> suffix to :<number>
        # e.g., "path/to/test.rb:::TestClass#test_method_L34" -> "path/to/test.rb:34"
        test_file_locations = with_location.map do |n|
          if n =~ /\A(.+?):::.+?_L(\d+)\z/
            "#{$1}:#{$2}"
          else
            n.partition(":::").first
          end
        end
        test_file_locations = test_file_locations.compact.uniq

        without_location_class = without_location
          .map { |n| n.split("#").first }
          .compact
          .uniq

        puts "without:", without_location_class

        output = test_file_locations.compact.uniq.sort
        File.write("/tmp/query-guard-tests.txt", output.join(" "))
      end
    end
  end
end
