# typed: false
# frozen_string_literal: true

module ActionsContentPolicy
  extend ActiveSupport::Concern

  BASE_CSP_URLS =
    [
      "https://*.actions.githubusercontent.com",
      "wss://*.actions.githubusercontent.com",
    ]

  DREAMLIFTER_CSP_URLS =
    BASE_CSP_URLS + [
      "https://productionresultssa0.blob.core.windows.net/",
      "https://productionresultssa1.blob.core.windows.net/",
      "https://productionresultssa2.blob.core.windows.net/",
      "https://productionresultssa3.blob.core.windows.net/",
      "https://productionresultssa4.blob.core.windows.net/",
      "https://productionresultssa5.blob.core.windows.net/",
      "https://productionresultssa6.blob.core.windows.net/",
      "https://productionresultssa7.blob.core.windows.net/",
      "https://productionresultssa8.blob.core.windows.net/",
      "https://productionresultssa9.blob.core.windows.net/",
      "https://productionresultssa10.blob.core.windows.net/",
      "https://productionresultssa11.blob.core.windows.net/",
      "https://productionresultssa12.blob.core.windows.net/",
      "https://productionresultssa13.blob.core.windows.net/",
      "https://productionresultssa14.blob.core.windows.net/",
      "https://productionresultssa15.blob.core.windows.net/",
      "https://productionresultssa16.blob.core.windows.net/",
      "https://productionresultssa17.blob.core.windows.net/",
      "https://productionresultssa18.blob.core.windows.net/",
      "https://productionresultssa19.blob.core.windows.net/",
    ]

  # These URLS are used by the Pipelines Devfabric Environment or the Fake Streaming Log service for development
  DREAMLIFTER_DEVELOPMENT_CSP_URLS = DREAMLIFTER_CSP_URLS + [
    "http://localhost:44445",
    "ws://localhost:44444",
    "ws://streaming-logs.localhost:44444",
    "https://*.codedev.ms",
    "http://*.codedev.ms",
    "wss://*.codedev.ms",
    "ws://*.codedev.ms",
    "https://*.codedev.localhost",
    "http://*.codedev.localhost",
    "wss://*.codedev.localhost",
    "ws://*.codedev.localhost",
    "http://devstoreaccount1.blob.codedev.localhost",
    "https://devstoreaccount1.blob.codedev.localhost",
  ]

  # For loading in Dreamlifter logs
  # Usage: before_action :add_dreamlifter_csp_exceptions, only: :show
  def add_dreamlifter_csp_exceptions
    return unless GitHub.actions_enabled?

    SecureHeaders.append_content_security_policy_directives(
      request,
      connect_src: dreamlifter_connect_sources,
    )
  end

  def dreamlifter_connect_sources
    return DREAMLIFTER_DEVELOPMENT_CSP_URLS if Rails.env.development?

    if GitHub.multi_tenant_enterprise? && GitHub.actions_results_storage_accounts.present?
      csp_urls = BASE_CSP_URLS.dup
      accts = GitHub.actions_results_storage_accounts.split(",").map(&:strip).uniq.reject { |a| a.include?("*") || a.empty? }
      accts.each do |name|
        csp_urls << "https://#{name}.blob.core.windows.net/"
      end
      return csp_urls
    end

    DREAMLIFTER_CSP_URLS
  end
end
