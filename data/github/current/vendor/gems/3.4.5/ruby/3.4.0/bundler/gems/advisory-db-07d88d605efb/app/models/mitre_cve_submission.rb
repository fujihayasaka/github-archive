# frozen_string_literal: true

class MITRECVESubmission < ApplicationRecord
  def self.record_cve_submission(cve_review:, pull_request_url:)
    transaction do
      submission = find_or_initialize_by(ghsa_id: cve_review.ghsa_id) do |record|
        record.pull_request_url = pull_request_url
      end

      submission.submit_json_v5(update: submission.persisted?)

      cve_review.submit_to_mitre!
      submission.save! && submission.touch # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def self.record_cve_rejection(cve_review:, rejection_params:)
    transaction do
      submission = find_or_initialize_by(ghsa_id: cve_review.ghsa_id) do |record|
        record.pull_request_url = "api"
      end

      cve_api_client = CVEAPI::Client.new
      cve_api_client.reject_cve(
        cve_review.assigned_cve_id,
        previously_published: submission.persisted?,
        rejected_reasons: [rejection_params[:reason]],
        replaced_by: [rejection_params[:replaced_by]].compact_blank,
      )
      cve_review.reject!
      submission.updated_at = Time.zone.now
      submission.save!
    end
  end

  belongs_to :cve_review,
    primary_key: :ghsa_id,
    foreign_key: :ghsa_id,
    optional: false,
    inverse_of: :mitre_cve_submissions

  delegate :assigned_cve_id, :branch_name, :cve_json_builder, to: :cve_review

  after_create do
    AdvisoryDB.stats.increment("curation.cve_submission")
  end

  def submit_json_v5(update: false)
    cve_json_string = cve_json_builder.to_json
    cna_json_string = JSON.generate(
      "cnaContainer" => JSON.parse(cve_json_string)["containers"]["cna"],
    )
    cve_api_client = CVEAPI::Client.new
    if update
      cve_api_client.update_cve(assigned_cve_id, cna_json_string)
    else
      cve_api_client.create_cve(assigned_cve_id, cna_json_string)
    end
  end
end
