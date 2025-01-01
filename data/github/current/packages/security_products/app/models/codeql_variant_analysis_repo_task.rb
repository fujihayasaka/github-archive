# typed: true
# frozen_string_literal: true

class CodeqlVariantAnalysisRepoTask < ApplicationRecord::Domain::RemoteQueries
  include ::Storage::Uploadable

  belongs_to :codeql_variant_analysis
  belongs_to :repository

  belongs_to :uploader, class_name: "User", foreign_key: :artifact_actor_id # rubocop:todo Rails/InverseOf
  alias_attribute :uploader_id, :artifact_actor_id
  alias_attribute :guid, :artifact_guid
  alias_attribute :size, :artifact_size
  alias_attribute :state, :artifact_state
  alias_attribute :name, :artifact_name
  alias_attribute :content_type, :artifact_content_type

  set_uploadable_policy_path :codeql_variant_analysis_repo_tasks
  add_uploadable_policy_attributes :repository_id, :codeql_variant_analysis_id

  before_validation :set_guid, on: :create
  before_validation :set_status, on: :create
  before_destroy :storage_delete_object_if_exists

  STATUSES = %w(pending in_progress succeeded failed canceled timed_out)
  NON_FINAL_STATUSES = %w(pending in_progress)
  FINAL_STATUSES = STATUSES - NON_FINAL_STATUSES

  enum :artifact_state, Storage::Uploadable::STATES

  validates :repository_id, presence: true
  validates :status, inclusion: { in: STATUSES, message: "not included in #{STATUSES}" }
  validates :failure_message, length: { maximum: MYSQL_TEXT_FIELD_LIMIT }, allow_nil: true
  validates :database_commit_sha,
            :source_location_prefix,
            :artifact_guid,
            length: { maximum: 255 },
            allow_nil: true
  validate :storage_ensure_inner_asset

  # BEGIN storage settings

  def storage_policy(actor: nil, repository: nil, key: nil)
    ::Storage::MemoryAlphaPolicy.new(self, actor: actor, repository: self.codeql_variant_analysis&.controller_repo)
  end

  # s3 storage settings

  def self.storage_s3_bucket
    GitHub.codeql_variant_analysis_memory_alpha_bucket
  end

  def self.storage_s3_new_bucket
    GitHub.codeql_variant_analysis_memory_alpha_bucket
  end

  def storage_s3_bucket
    self.class.storage_s3_new_bucket
  end

  def storage_s3_key(policy)
    "codeql-variant-analysis-repo-tasks/#{codeql_variant_analysis_id}/#{repository_id}/#{guid}"
  end

  def storage_s3_access_key
    GitHub.codeql_variant_analysis_memory_alpha_key_id
  end

  def storage_s3_secret_key
    GitHub.codeql_variant_analysis_memory_alpha_access_key
  end

  # This method is only used temporarily so we can feature flag in users. Once
  # memory alpha is done testing, we can remove this method and go back to either
  # just feature flagging in repos or removing the feature flag altogether.
  def memory_alpha_fastly_acceleration_bucket(actor, repository)
    nil
  end

  # END storage settings

  def storage_policy_api_url
    "/repositories/%s/code-scanning/codeql/variant-analyses/%s/repositories/%s" % [codeql_variant_analysis&.controller_repo_id, codeql_variant_analysis_id, repository_id]
  end

  private

  def set_status
    self.status = "pending"
  end
end
