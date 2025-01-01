# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AlertLinksController < AbstractRepositoryController
  include ScanningControllerMethods
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertLinkDependency

  allow_verified_fetch only: [:update]

  before_action :check_code_scanning_read
  before_action :writable_repository_required
  before_action :parse_json_params, only: [:update]

  def update
    alert_number = params[:number].to_i
    repository_id = current_repository.id

    # We need to convert all PR numbers to PR ids since
    # we don't have access to the db ids where this action is called from.
    pr_numbers = Set.new(
      Array(params[:links_to_create]).select(&:present?).filter_map { |link| link[:pull_request_number].to_i if link[:pull_request_number].to_i.positive? } +
      Array(params[:links_to_delete]).select(&:present?).filter_map { |link| link[:pull_request_number].to_i if link[:pull_request_number].to_i.positive? }
    )
    pr_issues_by_number = with_database_error_fallback(fallback: {}) do
      Issue.includes(:pull_request).not_spammy.where(repository_id:, number: pr_numbers).index_by(&:number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    branch_names = Set.new(
      Array(params[:links_to_create]).select(&:present?).filter_map { |link| link[:ref_name] if link[:ref_name].present? } +
      Array(params[:links_to_delete]).select(&:present?).filter_map { |link| link[:ref_name] if link[:ref_name].present? }
    )
    branches_by_name = current_repository.heads.select { |branch|  branch_names.include?(branch.name) }.index_by(&:name)

    to_create = Array(params[:links_to_create]).select(&:present?).map do |link|
      {
        alert_number:,
        pull_request_id: pr_issues_by_number[link[:pull_request_number].to_i]&.pull_request&.id,
        ref_name_bytes: branches_by_name[link[:ref_name]]&.qualified_name&.b,
      }
    end

    to_delete = Array(params[:links_to_delete]).select(&:present?).map do |link|
      {
        alert_number:,
        pull_request_id: pr_issues_by_number[link[:pull_request_number].to_i]&.pull_request&.id,
        ref_name_bytes:  branches_by_name[link[:ref_name]]&.qualified_name&.b,
      }
    end

    GitHub.dogstats.increment("code_scanning.showpage.update_links", tags: ["creation:#{to_create.present?}", "deletion:#{to_delete.present?}"])

    missing_alert_message = "Could not find the alert"

    if to_create.present?
      response = GitHub::Turboscan.create_alert_links(
        repository_id:,
        links: to_create
      )

      if response.blank? || response.error.present?
        if response&.error&.code == :not_found
          return render status: 422, json: { message: missing_alert_message }
        end
        return render status: 500, json: { message: "Could not create the alert links" }
      end
    end

    if to_delete.present?
      response = GitHub::Turboscan.delete_alert_links(
        repository_id:,
        links: to_delete
      )

      if response.blank? || response.error.present?
        if response&.error&.code == :not_found
          return render status: 422, json: { message: missing_alert_message }
        end
        return render status: 500, json: { message: "Could not delete the alert links" }
      end
    end

    response_links = CodeScanning::AlertLinks.load_for_single_alert(repository_id:, alert_number:)

    linked_branches = response_links.filter_map do |link|
      convert_to_branch_picker_props(T.must(link.branch), current_repository) if link.branch?
    end

    linked_pull_requests = response_links.filter_map do |link|
      convert_to_pull_request_picker_props(T.must(link.pull_request), current_repository) if link.pull_request?
    end

    message = "created: #{ to_create.length }, deleted: #{ to_delete.length }"
    render(json: { data: { message: message, linked_branches:, linked_pull_requests: } }, status: :ok)
  end
end
