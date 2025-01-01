# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AlertLinksController < AbstractRepositoryController
  include ScanningControllerMethods
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :check_code_scanning_write
  before_action :writable_repository_required
  before_action :parse_json_params, only: [:update]

  preload_features [
    :disable_code_scanning
  ]

  def update
    created = 0
    if params[:links_to_create].present?
      to_create = params[:links_to_create].map do |link|
        {
          alert_number: params[:number],
          pull_request_id: link[:pull_request_id],
          ref_name_bytes: link[:ref_name_bytes]
        }
      end

      created = to_create.length
    end

    deleted = 0
    if params[:links_to_delete].present?
      to_delete = params[:links_to_delete].map do |link|
        {
          alert_number: params[:number],
          pull_request_id: link[:pull_request_id],
          ref_name_bytes: link[:ref_name_bytes]
        }
      end

      deleted = to_delete.length
    end

    message = "created: #{ created }, deleted: #{ deleted }"
    render(json: { data: { message: message, current_links: [] } }, status: :ok)
  end
end
