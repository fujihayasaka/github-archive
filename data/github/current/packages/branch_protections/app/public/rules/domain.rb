# typed: strict
# frozen_string_literal: true

module Rules
  class Domain < GH::Domain::Base

    # Given repo_ids, find exemption requests for those repos
    sig do
      params(
        repo_ids: T::Array[Integer],
        request_type: T.nilable(String),
        start_date: T.nilable(Date),
        end_date: T.nilable(Date),
        ids: T.nilable(T::Array[Integer]),
        filter_expired: T::Boolean
      )
      .returns(T::Array[Integer])
    end
    def exemption_request_ids_by_repo_ids(repo_ids:, request_type: nil, start_date: nil, end_date: nil, ids: nil, filter_expired: true)
      scope = ::Exemptions::ExemptionRequest
      if filter_expired
        scope = scope.not_expired
      end

      scope = scope.where(repository_id: repo_ids)
      scope = scope.where(request_type: request_type) if request_type

      scope = scope.where(created_at: start_date.beginning_of_day..) if start_date
      scope = scope.where(created_at: ..end_date.end_of_day) if end_date
      scope = scope.where(id: ids) if ids

      scope.pluck(:id).to_a
    end

    # Calculate metrics for a set of exemption requests
    sig do
      params(
        exemption_request_ids: T::Array[Integer],
      )
      .returns(ExemptionMetricsResult)
    end
    def exemption_metrics(exemption_request_ids:)
      results = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, ids: exemption_request_ids))
        SELECT
            COUNT(ex_req.id) AS request_count,
            CAST(SUM(CASE WHEN ex_resp.status = 0 THEN 1 ELSE 0 END) AS UNSIGNED) AS approved_count,
            CAST(SUM(CASE WHEN ex_resp.status = 1 THEN 1 ELSE 0 END) AS UNSIGNED) AS rejected_count,
            CAST(SUM(CASE WHEN ex_resp.id IS NULL AND ex_req.status = 3 THEN 1 ELSE 0 END) AS UNSIGNED) AS cancelled_count,
            CAST(SUM(CASE WHEN ex_resp.id IS NULL AND ex_req.status = 0 THEN 1 ELSE 0 END) AS UNSIGNED) AS pending_count,
            CAST(SUM(CASE WHEN ex_resp.id IS NOT NULL THEN 1 ELSE 0 END) AS UNSIGNED) AS response_count,
            CAST(SUM(CASE WHEN ex_resp.id IS NOT NULL THEN TIMESTAMPDIFF(SECOND, ex_req.created_at, ex_resp.created_at) ELSE 0 END) AS UNSIGNED) AS total_response_time
        FROM
          exemption_requests ex_req
        LEFT JOIN
          (
            SELECT
              exemption_request_id,
              repository_id,
              MIN(created_at) AS earliest_created_at
            FROM
              exemption_responses
            GROUP BY
              exemption_request_id, repository_id
          ) exp_resp_earliest
        ON
          ex_req.id = exp_resp_earliest.exemption_request_id
          AND ex_req.repository_id = exp_resp_earliest.repository_id
        LEFT JOIN
          exemption_responses ex_resp
        ON
          ex_req.id = ex_resp.exemption_request_id
          AND ex_req.repository_id = ex_resp.repository_id
          AND ex_resp.created_at = exp_resp_earliest.earliest_created_at
        WHERE
          ex_req.id IN (:ids)
      SQL

      results = ExemptionMetricsResult.new(
        request_count: results[0][0].to_i,
        approved_count: results[0][1].to_i,
        rejected_count: results[0][2].to_i,
        cancelled_count: results[0][3].to_i,
        pending_count: results[0][4].to_i,
        response_count: results[0][5].to_i,
        total_response_time: results[0][6].to_i,
      )

      results
    end

    class ExemptionMetricsResult < T::Struct
      const :request_count, Integer
      const :approved_count, Integer
      const :rejected_count, Integer
      const :cancelled_count, Integer
      const :pending_count, Integer
      const :response_count, Integer
      const :total_response_time, Integer
    end
  end
end
