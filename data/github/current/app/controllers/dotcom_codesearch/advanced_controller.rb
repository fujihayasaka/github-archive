# typed: true
# frozen_string_literal: true

# This controller is only reachable in GHES installations.
class DotcomCodesearch::AdvancedController < CodesearchController
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_search_enabled

  javascript_bundle :search

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    @language = language
    @search   = sanitized_query
    render "dotcom_codesearch/advanced_search", locals: { blackbird_enabled: blackbird_enabled? }
  end
end
