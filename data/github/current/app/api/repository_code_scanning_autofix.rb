# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningAutofix < Api::App
  include Api::App::CodeScanningHelpers

  get "/repositories/:repository_id/code-scanning/alerts/:alert_number/fixes", operation_id: :internal do # we don't want to expose this endpoint
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    deliver_error! 404 unless CodeScanning::Autofix.enabled_for_repo?(repo)

    pull = find_pull_request_from_ref(repo, params["ref"])
    record_or_404 pull

    ensure_valid_alert_number!(alert_number)

    control_access :list_pull_request_comments,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ref_names_bytes = pull.code_scanning_latest_check_suite&.refs_bytes
    if pull.current_head_oid.blank? || ref_names_bytes.blank?
      deliver_error! 404, message: "No fix found for alert number #{alert_number}"
    end

    response = GitHub::Turboscan::SuggestedFixes.suggested_fix(
      repository_id: repo.id,
      alert_numbers: [alert_number],
      head_commit_oid: pull.current_head_oid,
      ref_names_bytes:,
    )

    if response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    fix = response.data&.suggested_fix_alerts&.[](alert_number)&.suggested_fix

    deliver_error! 404, message: "No suggested fix found for alert number #{alert_number}" if fix.nil? || fix.dismissed || fix.outdated

    csrc = CodeScanningReviewComment.find_by(repository: repo.id, pull_request: pull.id, alert_number: alert_number)
    record_or_404 csrc

    GlobalInstrumenter.instrument("code_scanning.autofix_event", {
      repository_id: repo.id,
      alert_number: alert_number,
      event_type: :AUTOFIX_EVENT_TYPE_EDITED,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
    })

    deliver :code_scanning_suggested_fix_hash, { fix: fix, csrc: csrc }
  end

  private

  def alert_number
    int_id_param!(key: :alert_number)
  end
end
