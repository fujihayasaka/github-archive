# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class MetricsPayloadBuilder
        extend T::Sig

        sig { params(metrics: SecretScanning::Models::PushProtectionMetrics).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def push_protection_metrics(metrics)
          {
            total_blocks_count: metrics.total_block_count,
            successful_blocks_count: metrics.successful_block_count,
            bypassed_alerts_count: metrics.bypassed_alert_count,
            bypass_requests_count: metrics.bypass_requests_count,
            mean_response_time: metrics.mean_response_time,
            # limit to 4 results
            blocks_by_token_type_counts: counts_by_token_type(metrics.blocks_by_token_type_counts).slice(0, 4),
            blocks_by_repository_counts: counts_by_repo(metrics.blocks_by_repository_counts).slice(0, 4),
            bypasses_by_token_type_counts: counts_by_token_type(metrics.bypasses_by_token_type_counts).slice(0, 4),
            bypasses_by_repository_counts: counts_by_repo(metrics.bypasses_by_repository_counts).slice(0, 4),
            bypasses_by_reason_counts: metrics.bypasses_by_reason_counts.map do |count|
              {
                type: "BYPASS_REASON",
                name: bypass_reason_label(count.bypass_reason),
                count: count.count,
                percent: count.percent
              }
            end,
            bypasses_by_request_status_counts: metrics.bypasses_by_request_status_counts.map do |count|
              {
                type: "BYPASS_REQUEST_STATUS",
                name: bypass_status_label(count.bypass_request_status),
                count: count.count,
                percent: count.percent,
              }
            end
          }
        end

        sig do
          params(
            result: SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]]
          ).returns(T::Hash[T.untyped, T.untyped])
        end
        def token_type_counts(result)
          {
            counts: counts_by_token_type(result.data),
            next_cursor: result.next_cursor,
            previous_cursor: result.previous_cursor,
          }
        end

        sig do
          params(
            result: SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]]
          ).returns(T::Hash[T.untyped, T.untyped])
        end
        def repo_counts(result)
          {
            counts: counts_by_repo(result.data),
            next_cursor: result.next_cursor,
            previous_cursor: result.previous_cursor,
          }
        end

        private

        sig do
          params(
            counts_by_token_type: T::Array[SecretScanning::Models::TokenTypeCountMetric])
            .returns(T::Array[{ type: String, name: String, slug: String, count: Integer, is_custom_pattern: T::Boolean, has_metadata: T::Boolean }])
        end
        def counts_by_token_type(counts_by_token_type)
          counts_by_slug = {}

          counts_by_token_type.each do |metric|
            metadata = metric.token_metadata

            name = metric.token_type
            slug = metric.token_type
            is_custom_pattern = false

            unless metadata.nil?
              name = metadata.label
              slug = metadata.slug
              is_custom_pattern = metadata.is_custom_pattern?
            end

            if counts_by_slug.has_key?(slug)
              counts_by_slug[slug][:count] += metric.count
            else
              counts_by_slug[slug] = {
                type: "TOKEN_TYPE",
                name: name,
                slug: slug,
                count: metric.count,
                is_custom_pattern: is_custom_pattern,
                has_metadata: !metadata.nil?
              }
            end
          end

          # since we merged counts, we have to re-sort
          counts_by_slug.values.sort_by! { |metric| [metric[:count] * -1, metric[:name]] }
        end

        sig do
          params(
            counts_by_repo_id: T::Array[SecretScanning::Models::RepoCountMetric])
            .returns(T::Array[{ type: String, name: T.nilable(String), count: Integer }])
        end
        def counts_by_repo(counts_by_repo_id)
          counts_by_repo_id.map do |repo_count|
            {
              type: "REPOSITORY",
              name: repo_count.repo_name,
              count: repo_count.count,
            }
          end
        end

        # Return the label for the given bypass reason symbol
        sig { params(reason: T.any(Symbol, Integer)).returns(String) }
        def bypass_reason_label(reason)
          case reason
          when :FALSE_POSITIVE
            "False positives"
          when :USED_IN_TESTS
            "Used in tests"
          when :WILL_FIX_LATER
            "Fix later"
          else
            raise ArgumentError.new("Invalid bypass reason: #{reason}")
          end
        end

        # Return the label for the given bypass request status symbol
        sig { params(status: T.any(Symbol, Integer)).returns(String) }
        def bypass_status_label(status)
          case status
          when :pending
            "Open"
          when :approved
            "Approved"
          when :rejected
            "Rejected"
          when :cancelled
            "Cancelled"
          else
            raise ArgumentError.new("Invalid bypass request status: #{status}")
          end
        end
      end
    end
  end
end
