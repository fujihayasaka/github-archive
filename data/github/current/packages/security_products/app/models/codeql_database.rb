# typed: true
# frozen_string_literal: true

class CodeqlDatabase < ApplicationRecord::Domain::RemoteQueries
  include ::Storage::Uploadable
  include GitHub::Validations
  include CodeqlDatabase::ZipValidation

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  serialize :commit_oid, coder: GitHub::Hex

  set_uploadable_policy_path :codeql_databases
  add_uploadable_policy_attributes :repository_id, :language, :commit_oid

  set_content_types \
    "application/zip" => ".zip",
    "application/x-zip-compressed" => ".zip"

  validates :repository, :uploader, :size, presence: true
  validate :storage_ensure_inner_asset
  validates :name, unicode3: true, length: { maximum: 255 }

  # mysql column limit is 2GB
  validates_numericality_of :size, greater_than_or_equal_to: 1, less_than_or_equal_to: 2.gigabytes

  before_validation :set_guid, on: :create
  validates_inclusion_of :content_type, in: allowed_content_types

  before_destroy :storage_delete_object_if_exists

  # Find databases with the given repository ID and language pairs.
  #
  # When using this, always be aware of the size of the input array and use batching
  # such as `each_slice` if necessary before building the SQL query.
  # This scope will fail with a stack overflow at around 2000 elements.
  #
  # names_with_owners - Array of [Number, String] elements like [[123, "javascript"], [456, "ruby"]]
  scope :repos_and_languages, -> (repo_language_pairs) {
    where(repo_language_pairs
      .map { |repo_id, language| arel_table[:repository_id].eq(repo_id).and(arel_table[:language].eq(language)) }
      .reduce { |all_conditions, condition| all_conditions.or(condition) })
  }

  enum :state, Storage::Uploadable::STATES

  # How long a generated signed URL for downloading a database is valid for.
  STORAGE_DOWNLOAD_EXPIRATION = 1.day

  # How long is the upload of a database allowed to take. Trying to finalise
  # the upload of a database older than this will fail.
  UPLOAD_TIMEOUT = 1.hour

  # BEGIN storage settings

  def storage_policy(actor: nil, repository: nil, key: nil)
    ::Storage::MemoryAlphaPolicy.new(self, actor: actor, repository: self.repository)
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
    "database/#{repository_id}/#{language}/#{guid}"
  end

  def storage_s3_access_key
    GitHub.codeql_variant_analysis_azure_storage_account
  end

  def storage_s3_secret_key
    GitHub.codeql_variant_analysis_memory_alpha_secret
  end

  # END storage settings

  def storage_policy_api_url
    "/repositories/%s/code-scanning/codeql/databases/%s/%d" % [repository_id, language, id]
  end

  # Determines if CodeQL databases exist for a set of repository/language pairs.
  # The repos_and_languages argument is expected to be of the form [repo_id, language][].
  # Returns a set of [repo_id, language] pairs.
  def self.repos_and_languages_with_database(repos_and_languages)
    repos_and_languages.each_slice(500).flat_map do |repos_and_languages_slice|
      where(state: :uploaded)
        .repos_and_languages(repos_and_languages_slice)
        .group(:repository_id, :language)
        .pluck(:repository_id, :language)
    end.to_set
  end

  # Fetches the latest databases for a set of repository/language pairs.
  # The repos_and_languages argument is expected to be of the form [repo_id, language][].
  # Returns a map from [repo_id, language] pairs to CodeqlDatabase objects.
  # The keys of the returned map will be a subset of the input array, and any
  # missing elements indicates that there is no database for that repository/language pair.
  def self.latest_for_repos_and_languages(repos_and_languages)
    repos_and_languages.each_slice(500).flat_map do |repos_and_languages_slice|
      latest_for_repos_and_languages_internal(repos_and_languages_slice)
        .group_by { |d| [d.repository_id, d.language] }
        .map { |_k, v| v.first }
    end.index_by { |d| [d.repository_id, d.language] }
  end

  # Determines if the latest databases for each repository/language pair was uploaded by
  # a user or by the bulk builder.
  # The repos_and_languages argument is expected to be of the form [repo_id, language][].
  # Returns a filtered set of [repo_id, language] pairs, where inclusion indicates the
  # latest databases was uploaded by a user.
  def self.latest_database_is_user_uploaded(repos_and_languages, bulk_builder_user_id)
    repos_and_languages.each_slice(500).flat_map do |repos_and_languages_slice|
      latest_for_repos_and_languages_internal(repos_and_languages_slice)
        .pluck(:repository_id, :language, :uploader_id)
        .group_by { |repo_id, language, _uploader_id| [repo_id, language] }
        .map { |_k, v| v.first }
        .select { |_repo_id, _language, uploader_id| uploader_id != bulk_builder_user_id }
        .map { |repo_id, language, _uploader_id| [repo_id, language] }
    end.to_set
  end

  # Produces an active record query to fetch the latest database for the given set of
  # repository id and language pairs.
  #
  # For best performance use an input list of at most 500 repo/langauge pairs.
  # Manual testing showed that this query starts to slow down considerably after this point:
  # https://github.com/github/github/pull/210707#discussion_r815850799
  #
  # Note that this query could return multiple rows for a repo/language pair if there are two
  # databases with the same upload time. In that case we consider the database with the higher ID
  # to be the canonical "latest" database. The results are ordered by ID, so code that calls
  # this method should group by repo_id and language and then take the first result.
  # e.g. .group_by { |d| [d.repo_id, d.language] }.map { |k, v| v.first }
  private_class_method def self.latest_for_repos_and_languages_internal(repos_and_languages)
    subquery = select("repository_id, language, max(created_at)")
      .repos_and_languages(repos_and_languages)
      .where(state: :uploaded)
      .group(:repository_id, :language)

    where(state: :uploaded)
      .repos_and_languages(repos_and_languages)
      .where("(repository_id, language, created_at) in (:sub)", sub: subquery)
      .order(id: :desc)
  end

  # Returns an array of CodeqlDatabase containing the latest databases for all
  # languages, or a single particular language, for the specified repository.
  # If min_age is specified, will only consider databases that are at least this old.
  def self.latest_for_repo(repository_id, min_age: nil)
    latest_for_repo_and_language_internal(repository_id, nil, min_age)
  end

  # Returns a single of CodeqlDatabase that is the latest database for
  # a single particular language for the specified repository.
  def self.latest_for_repo_and_language(repository_id, language)
    latest_for_repo_and_language_internal(repository_id, language, nil).first
  end

  private_class_method def self.latest_for_repo_and_language_internal(repository_id, language, min_age)
    subquery = select("language, max(created_at)")
    subquery = subquery.where(language: language) unless language.nil?
    subquery = subquery.where("created_at < ?", min_age.ago) unless min_age.nil?
    subquery = subquery.where(state: :uploaded)
      .where(repository_id: repository_id)
      .group(:language)

    databases = where("(language, created_at) in (:sub)", sub: subquery)
      .where(repository_id: repository_id, state: :uploaded)
      .order(id: :desc)
      .group_by { |database| database.language }
      .map { |_k, v| v.first }
  end
end
