# frozen_string_literal: true

class CVEReviewsBulkOperationsController < InboxController
  MAX_BULK_ASSIGNMENT_SIZE = 100

  def bulk_assignment
    ghsa_ids = params[:ghsa_ids]
    assignee = params[:assignee]

    if ghsa_ids.blank? || !ghsa_ids.is_a?(Array)
      render json: { error: "ghsa_ids must be a non-empty array" }, status: :bad_request
      return
    end

    if ghsa_ids.size > MAX_BULK_ASSIGNMENT_SIZE
      render json: { error: "ghsa_ids cannot exceed #{MAX_BULK_ASSIGNMENT_SIZE} items" }, status: :bad_request
      return
    end

    assignee_value = assignee.presence
    if assignee_value.present? && AdvisoryDB::Config::ActiveCurators::CURATORS.exclude?(assignee_value)
      render json: { error: "Invalid assignee: #{assignee_value}" }, status: :unprocessable_entity
      return
    end

    error_hash = {}
    CVEReview.where(ghsa_id: ghsa_ids).find_each do |cve_review|
      cve_review.update!(assignee: assignee_value)
    rescue StandardError => error
      error_hash[cve_review.ghsa_id] = "CVE review #{cve_review.ghsa_id} could not be assigned: #{error.message}"
      Failbot.report!(error, { context: "Bulk assignment failed for CVE review #{cve_review.ghsa_id}" })
    end

    render json: { success: error_hash.empty?, errorHash: error_hash }
  end
end
