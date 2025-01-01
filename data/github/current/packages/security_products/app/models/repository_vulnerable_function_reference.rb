# typed: strict
# frozen_string_literal: true

class RepositoryVulnerableFunctionReference < ApplicationRecord::Notify
  # Currently we only have exposure analysis for python alerts
  # We will add support for other ecosystems in the future
  VEA_SUPPORTED = T.let(["pip"], T::Array[String])

  # We are currently only supporting npm alerts for preview
  # We will add support for other ecosystems in the future
  VEA_PREVIEW = T.let(["npm"], T::Array[String])

  extend T::Sig
  belongs_to :repository_vulnerability_exposure_update, inverse_of: :repository_vulnerable_function_references
  belongs_to :repository_vulnerability_alert, inverse_of: :repository_vulnerable_function_references
  belongs_to :repository
  belongs_to :vulnerable_version_range

  validates :repository_vulnerability_exposure_update_id,
    :repository_vulnerability_alert_id,
    :repository_id,
    :vulnerable_version_range_id,
    :filename,
    :function_name,
    :commit_oid,
    :start_line,
    :start_column,
    :end_line,
    :end_column,
    presence: true

  sig { returns(String) }
  def blob_path
    "/#{repository&.name_with_owner}/blob/#{commit_oid}/#{filename}#L#{start_line}-L#{end_line}"
  end

  sig { returns(T::Boolean) }
  def public_ecosystem?
    VEA_SUPPORTED.include?(T.must(vulnerable_version_range).ecosystem)
  end

  sig { returns(T::Boolean) }
  def preview_ecosystem?
    VEA_PREVIEW.include?(T.must(vulnerable_version_range).ecosystem)
  end
end
