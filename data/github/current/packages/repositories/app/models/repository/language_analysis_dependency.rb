# typed: true
# frozen_string_literal: true

# Language-analysis related methods
module Repository::LanguageAnalysisDependency
  extend T::Helpers

  requires_ancestor { Repository }

  DELETE_BATCH_SIZE = 100

  # Public: the language analysis for this repository
  def language_analysis
    @language_analysis ||= LanguageAnalysis.new(self)
  end

  # Public: re-analyze this repository's language information
  def analyze_languages
    LanguageAnalyzer.new(self).analyze
  end

  def copy_language_stats_from_repo(copy_from_repo_id)
    Language.transaction do
      existing_ids = self.languages.pluck(:id)
      affected_rows = Language.connection.update(Arel.sql(<<-SQL, repository_id: id, copy_id: copy_from_repo_id))
        INSERT INTO languages (repository_id, language_name_id, size, total_size, created_at, updated_at, public)
        SELECT :repository_id, language_name_id, size, total_size, NOW(), NOW(), public FROM languages
        WHERE repository_id = :copy_id
      SQL
      if existing_ids.any?
        existing_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
          Language.where(repository_id: id, id: slice).delete_all
        end
      end
      affected_rows
    end
  end

  def enqueue_analyze_language_breakdown
    RepositoryUpdateLanguageStatsJob.perform_later(id)
  end

  # Retrieve a list of languages and percentages for this repository.
  #
  # Uses a read-through cache.
  #
  # Returns an Array of [ ["language_name", percent ], ... ]
  # in descending order by percentage.
  def language_percentages
    GitHub.cache.fetch(languages_summary_cache_key, ttl: 1.day, stats_key: "repo_top_languages.cache") do
      language_analysis.language_percentages
    end
  end

  # Does the repository include content written in a given language?
  #
  # language_name - the String name of the language
  #
  # Returns a Boolean.
  def includes_files_in_language?(language_name)
    language_percentages.map { |name, _| name.downcase }.include?(language_name.downcase)
  end

  # Calculate the per-file language breakdown for this repository
  #
  # oid - the object id (sha-ish) to analyze, defaults to the default oid.
  #
  # Returns a Hash of { "language_name" => [ "filename", ... ], ... }
  def files_by_language(oid = nil)
    commit_oid = oid || default_oid
    return Hash.new unless commit_oid

    GitHub.dogstats.time "repository", tags: ["action:files_by_language"] do
      incremental = true # always build on previous results when possible
      repository.rpc.language_breakdown_by_file(commit_oid, incremental)
    end
  end

  # Public: the language sizes for this repository as a Hash.
  #
  # Returns a Hash of { "language_name" => size, ... }
  def language_breakdown
    sizes = language_analysis.language_sizes
    Hash[*sizes.flatten]
  end

  # Public: calculate a language size analysis using linguist and GitRPC.
  #
  # commit_oid - The commit oid to analyze. Required.
  #
  # Returns a Hash of { "LanguageName" => size, ... }
  def language_size_analysis(commit_oid)
    GitHub.dogstats.time "repository", tags: ["action:language_size_analysis"] do
      # Use the previous scan as a starting point for the next one, analyzing
      # only the files that have changed since then:
      incremental = true
      # We have found that using 500,000 as the maximum tree size supports reasonably large repositories such as github/github, with very additional minimal performance impact.
      tree_size = 5 * Linguist::Repository::MAX_TREE_SIZE
      repository.rpc.language_stats(commit_oid, incremental, tree_size)
    end
  end

  # Internal: cache key for languages summary as shown on repository pages.
  def languages_summary_cache_key
    fail if new_record?
    ["repository", id, pushed_at.to_i, "languages-summary", "v9"].compact.join(":")
  end

  # Public: invalidate the rpc language cache.
  def invalidate_languages_rpc_cache
    repository.rpc.clear_language_cache
  end

  # Condense languages <= 1% into Other if there is more than one language that meets this condition.
  # If there is only 1 language that meets this condition, just list it as is.
  def top_languages_summarized
    percents = language_percentages

    if percents.length > 6
      percents, other = percents.take(6), percents.drop(6)
    else
      percents, other = percents.partition { |_lang, percent| percent > 1 }
    end

    if other.length == 1
      if other.first[1] > 0.0
        percents += other
      end
    else
      total = other.sum { |_k, v| v }
      if total > 0
        percents << ["Other", total.round(1)]
      end
    end
    percents
  end

  # Internal: Update the `primary_language` association with a new language,
  # and populate the the primary_language_name cache from the
  # `primary_language` association.
  def update_primary_language!(language)
    reload_raw_data # Ensure raw_data is as fresh as possible to avoid overwriting values

    self.primary_language_name_id = language.id # association
    self.primary_language_name = language.name # cached name value
    save!
  end

  # Internal: Unset the `primary_language`. For cases where no language is
  # now detected for a repository. `primary_language_name` cache needs
  # setting to nil also.
  def unset_primary_language!
    reload_raw_data # Ensure raw_data is as fresh as possible to avoid overwriting values

    self.primary_language_name_id = nil # association
    self.primary_language_name = nil # cached name value
    save!
  end
end
