# typed: true
# frozen_string_literal: true

require "turboquality"

class Api::RepositoryCodeQuality < Api::App
  include Api::App::CodeQualityHelpers

  get "/repositories/:repository_id/code-quality/findings", operation_id: "code-quality/list-findings-for-repo", read_from_replicas: true do
    repo = find_repo!

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:code_quality_findings_api, repo, repo.owner, default: false)

    control_access :read_code_quality,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: code_quality_forbid_read_message

    ensure_code_quality_available!(repo)
    ensure_code_quality_enabled!(repo)

    ensure_non_conflicting_cursor_params!

    filter = Turboquality::Proto::RuleFindingsFilter.new(finding_state: Turboquality::Proto::FindingState::FINDING_STATE_OPEN)
    if params[:state].present? && params[:state] == "dismissed"
      filter.finding_state = Turboquality::Proto::FindingState::FINDING_STATE_DISMISSED
    end

    request = Turboquality::Proto::GetFindingsRequest.new(
      repository_id: repo.id,
      page_size: per_page,
      cursor: params[:before] || params[:after],
      filter: filter,
      include_rule: true,
    )

    if params[:direction].present?
      request.sort_order = params[:direction] == "asc" ? Turboquality::Proto::FindingsSortOrder::FINDINGS_SORT_CREATED_ASCENDING : Turboquality::Proto::FindingsSortOrder::FINDINGS_SORT_CREATED_DESCENDING
    end

    response = begin
      GitHub::Turboquality.client.get_findings(request)
    rescue => error
      Failbot.report(error)
      nil
    end

    if response&.error&.code == :not_found
      deliver_error! 404
    elsif response.blank? || response.error.present?
      deliver_code_quality_unavailable_error!
    end

    data = response.data
    setup_cursor_links(data)

    deliver :code_quality_findings_hash, { findings: data.findings.to_a }, repo: repo
  end

  get "/repositories/:repository_id/code-quality/findings/:finding_number", operation_id: "code-quality/get-finding", read_from_replicas: true do
    repo = find_repo!

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:code_quality_findings_api, repo, repo.owner, default: false)

    control_access :read_code_quality,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: code_quality_forbid_read_message

    ensure_code_quality_available!(repo)
    ensure_code_quality_enabled!(repo)

    finding_number = int_id_param!(key: :finding_number)
    ensure_valid_finding_number!(finding_number)

    response = begin
      GitHub::Turboquality.client.get_finding(Turboquality::Proto::GetFindingRequest.new(
        repository_id: repo.id,
        number: finding_number,
      ))
    rescue => error
      Failbot.report(error)
      nil
    end

    if response&.error&.code == :not_found
      deliver_error! 404, message: "No finding found for finding number #{finding_number}"
    elsif response.blank? || response.error.present?
      deliver_code_quality_unavailable_error!
    end

    finding = response.data.finding

    deliver :code_quality_finding_hash, finding, repo: repo
  end

  private

  sig { params(data: Turboquality::Proto::GetFindingsResponse).void }
  def setup_cursor_links(data)
    prev_cursor = data.prev_cursor
    next_cursor = data.next_cursor
    if prev_cursor.present?
      @links.add_current({ before: prev_cursor, after: nil }, rel: "prev")
      @links.add_current({ before: nil, after: "" }, rel: "first")
    end
    if next_cursor.present?
      @links.add_current({ before: nil, after: next_cursor }, rel: "next")
      @links.add_current({ before: "", after: nil }, rel: "last")
    end
  end
end
