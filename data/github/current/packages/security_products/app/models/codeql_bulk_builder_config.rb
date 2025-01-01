# typed: true
# frozen_string_literal: true

class CodeqlBulkBuilderConfig < ApplicationRecord::Domain::RemoteQueries
  include GitHub::Validations

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  validates :repository, :language, :last_attempted, presence: true

  # Only support the built in set of CodeQL languages and not any user-defined languages
  ALLOWED_LANGUAGES = %w(cpp csharp go java javascript python ruby rust swift)
  validates :language, inclusion: { in: ALLOWED_LANGUAGES }

  # Find configs with the given repository ID and language pairs.
  # Returns active and inactive configs
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

  # Timestamp used for events that have never happened.
  # Allows them to come before all other timestamps when querying.
  NEVER_HAPPENED = Time.new(0)

  # Updates the last_attempted timestamp for the given repositories/languages.
  sig { params(repo_language_pairs: T::Array[[Integer, String]]).void }
  def self.update_last_updated(repo_language_pairs)
    now = Time.now
    repo_language_pairs.each_slice(1000) do |slice|
      repos_and_languages(slice).update_all(last_attempted: now)
    end
  end

  # Filters the given list of repo/language pairs to only those that are not currently onboarded.
  # Returns a set of repo/language pairs.
  def self.not_onboarded(repo_language_pairs)
    repo_language_pairs.each_slice(1000).flat_map do |slice|
      existing = repos_and_languages(slice).pluck(:repository_id, :language).to_set
      slice.select { |repo_id, language| !existing.include?([repo_id, language]) }
    end.to_set
  end

  # Filter out repos that don't have the language they are onboarded for
  # Returns two arrays, the first containing the repos with languages and the second containing the repos without languages
  def self.partition_repos_without_languages(repo_language_pairs)
    codeql_languages = repo_language_pairs.map { |_, language| language }.uniq
    all_linguist_names = codeql_languages.flat_map { |language| CodeqlVariantAnalysis::CODEQL_TO_LINGUIST_LANGUAGES[language] }
    language_name_ids = LanguageName.where(name: all_linguist_names).pluck(:name, :id).to_h

    repo_ids = repo_language_pairs.map { |repo_id, _| repo_id }
    language_and_repos = Language.where(repository_id: repo_ids, language_name_id: language_name_ids.values).pluck(:repository_id, :language_name_id)

    repos_with_language, repos_without_language = repo_language_pairs.partition do |repo_id, language, _|
      linguist_names = CodeqlVariantAnalysis::CODEQL_TO_LINGUIST_LANGUAGES[language]
      linguist_names.any? do |linguist_name|
        language_name_id = language_name_ids[linguist_name]
        language_and_repos.include? [repo_id, language_name_id]
      end
    end

    [repos_with_language, repos_without_language]
  end
end
