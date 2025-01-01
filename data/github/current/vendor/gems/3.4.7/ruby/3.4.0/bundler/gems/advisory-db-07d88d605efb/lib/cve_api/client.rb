# frozen_string_literal: true

require "rack"
require "uri"

module CVEAPI
  class Client
    BASE_URL = AdvisoryDB.cve_services_api_url
    CVEAPIClientError = Class.new(StandardError)

    delegate :cve_api_user, :cve_api_org, :cve_api_key, to: :AdvisoryDB

    def get_org_quota # rubocop:disable Naming/AccessorMethodName
      response = connection.get("/api/org/#{cve_api_org}/id_quota")

      unless response.success?
        raise CVEAPIClientError, JSON.dump(response.body)
      end

      response.body
    rescue Faraday::ConnectionFailed => error
      raise CVEAPIClientError, error.message
    end

    def get_cve(cve_id)
      response = connection.get("/api/cve/#{cve_id}")

      unless response.success?
        raise CVEAPIClientError, JSON.dump(response.body)
      end

      response.body
    rescue Faraday::ConnectionFailed => error
      raise CVEAPIClientError, error.message
    end

    def reserve_cve(amount: 1, cve_year: Date.current.year)
      query = Rack::Utils.build_query(
        amount: amount,
        cve_year: cve_year,
        short_name: cve_api_org,
        batch_type: "sequential",
      )

      response = connection.post("/api/cve-id?#{query}")

      unless response.success?
        raise CVEAPIClientError, JSON.dump(response.body)
      end

      response.body["cve_ids"]
    rescue Faraday::ConnectionFailed => error
      raise CVEAPIClientError, error.message
    end

    def create_cve(cve_id, cve_body)
      response = connection.post("/api/cve/#{cve_id}/cna", cve_body)

      unless response.success?
        raise CVEAPIClientError, JSON.dump(response.body)
      end

      response.body["created"]
    rescue Faraday::ConnectionFailed => error
      raise CVEAPIClientError, error.message
    end

    def reject_cve(cve_id, rejected_reasons:, replaced_by: [], previously_published: true)
      cve_hash = {
        cnaContainer: {
          rejectedReasons: rejected_reasons.map do |rejected_reason|
            {
              lang: "en",
              value: rejected_reason,
            }
          end,
        },
      }
      if replaced_by.present?
        cve_hash[:cnaContainer][:replacedBy] = replaced_by
      end
      cve_body = JSON.generate(cve_hash)

      response = if previously_published
                   connection.put("/api/cve/#{cve_id}/reject", cve_body)
                 else
                   connection.post("/api/cve/#{cve_id}/reject", cve_body)
                 end

      unless response.success?
        raise CVEAPIClientError, JSON.dump(response.body)
      end

      response.body["updated"]
    rescue Faraday::ConnectionFailed => error
      raise CVEAPIClientError, error.message
    end

    def update_cve(cve_id, cve_body)
      response = connection.put("/api/cve/#{cve_id}/cna", cve_body)

      unless response.success?
        raise CVEAPIClientError, JSON.dump(response.body)
      end

      response.body["updated"]
    rescue Faraday::ConnectionFailed => error
      raise CVEAPIClientError, error.message
    end

    private

    def connection
      @connection ||= Faraday.new(
        BASE_URL,
        headers: {
          "CVE-API-USER" => cve_api_user,
          "CVE-API-ORG" => cve_api_org,
          "CVE-API-KEY" => cve_api_key,
        },
      ) do |faraday|
        faraday.request :json
        faraday.request :retry
        faraday.response :json
        faraday.adapter :net_http
      end
    end
  end
end
