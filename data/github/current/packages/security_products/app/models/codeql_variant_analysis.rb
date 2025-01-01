# typed: true
# frozen_string_literal: true

class CodeqlVariantAnalysis < ApplicationRecord::Domain::RemoteQueries
  has_many :codeql_variant_analysis_repo_tasks
  belongs_to :controller_repo, class_name: "Repository", foreign_key: :controller_repo_id # rubocop:todo Rails/InverseOf
  belongs_to :actor, class_name: "User", foreign_key: :actor_id # rubocop:todo Rails/InverseOf

  FAILURE_REASONS = %w(no_repos_queried internal_error)
  # Maps from CodeQL language names to linguist language names as found in the LanguageName table.
  CODEQL_TO_LINGUIST_LANGUAGES = {
    "cpp": ["C", "C++"],
    "csharp": ["C#"],
    "go": ["Go"],
    "java": %w[Java Kotlin],
    "javascript": %w[JavaScript TypeScript],
    "python": ["Python"],
    "ruby": ["Ruby"],
    "rust": ["Rust"],
    "swift": ["Swift"],
  }.with_indifferent_access
  ALLOWED_LANGUAGES = CODEQL_TO_LINGUIST_LANGUAGES.keys

  validates :controller_repo_id, presence: true
  validates :actor_id, presence: true
  validates :query_language,
            presence: true,
            length: { maximum: 255 },
            inclusion: { in: ALLOWED_LANGUAGES, message: "not included in #{ALLOWED_LANGUAGES}" }
  validates :query_pack_path, length: { maximum: MYSQL_TEXT_FIELD_LIMIT }, allow_nil: true
  validates :failure_reason, inclusion: { in: FAILURE_REASONS, message: "not included in #{FAILURE_REASONS}" }, allow_nil: true
  validates :over_limit_repo_ids,
            :no_codeql_db_repo_ids,
            :privacy_mismatch_repo_ids,
            :not_found_repo_nwos,
            length: { maximum: MYSQL_TEXT_FIELD_LIMIT },
            allow_nil: true

  VARIANT_ANALYSIS_ID_REGEX = %r{/variant-analyses/(?<variant_analysis_id>\d+)(/|$)}

  def self.load_variant_analysis_from_path_param(env, path)
    if match = VARIANT_ANALYSIS_ID_REGEX.match(path)
      ActiveRecord::Base.connected_to(role: :reading) do
        CodeqlVariantAnalysis.find_by(id: match[:variant_analysis_id])
      end
    end
  end
end
