# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job listens to PR review thread resolution events
# If they relate to a review by the Code Scanning bot,
# it emits another Hydro event.
#
# Those events are used in Product360 for our engagement data:
# - https://github.com/github/airflow-sources/blob/c61599670f52d8fa355905e1ad12a2311188ac2f/dags/enterprise_core_metrics/canonical/product_360/product_config_files/product_config_code_scanning.py#L200
# - https://dataexplorer.azure.com/dashboards/3b755899-1035-4e2d-9459-078e624a0bd5
class HydroEmitCodeScanningReviewResolveJob < HydroMessageJob
  queue_as :hydro_emit_code_scanning_review_resolve

  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    thread = PullRequestReviewThread.find_by(id: message[:pull_request_review_thread][:id])
    return unless thread
    first_comment = thread.review_comments.first
    return unless first_comment

    return unless first_comment.user&.bot?
    return unless T.cast(first_comment.user, Bot).slug == Apps::Privileged::CodeScanning::GHAS_BOT_LOGIN

    GlobalInstrumenter.instrument("code_scanning.pull_request_review_comment_resolve", message)
  end
end
