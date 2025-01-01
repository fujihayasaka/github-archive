# typed: true
# frozen_string_literal: true

class LanguageAnalyzer

  class Diff
    # Internal: Hashes containing ids and sizes of existing language records,
    # indexed by String language name.
    attr_reader :existing_ids, :existing_sizes

    # Internal: a Hash of LanguageName instances indexed by String language name.
    attr_reader :language_names

    # Internal: a Hash containing newly calculated language sizes, indexed by
    # String language name.
    attr_reader :new_sizes

    # Initialize a new language analyzer diff.
    #
    # new_sizes        - A Hash of {"LanguageName" => size, ...} of
    #                    newly-calculated analysis data.
    # existing_records - An Array of [ [id, name, size], ... ] for existing
    #                    language records.
    # language_names   - A Hash of { "Name" => <LanguageName> } for all the
    #                    language names listed in the new_sizes hash.
    def initialize(new_sizes, existing_records, language_names)
      @new_sizes      = new_sizes
      @language_names = language_names
      @existing_ids   = {}
      @existing_sizes = {}

      existing_records.each do |id, name, size|
        @existing_ids[name]   = id
        @existing_sizes[name] = size
      end
    end

    # Internal: String language names that are new.
    def new_names
      new_sizes.keys - existing_ids.keys
    end

    # Internal: String language names that need to be checked for changes.
    def updated_names
      existing_ids.keys & new_sizes.keys
    end

    # Internal: String language names that need to be deleted.
    def deleted_names
      existing_ids.keys - new_sizes.keys
    end

    # Public: language records that need to be inserted
    #
    # Returns an Array of [ [ language_name.id, size ], ... ]
    def to_insert
      new_names.select { |name| new_sizes[name] > 0 }.map do |name|
        [language_names[name].id, new_sizes[name]]
      end
    end

    # Public: language records that need to be updated.
    #
    # Returns an Array of [ [ language_id, size ], ... ]
    def to_update
      updates = updated_names.map do |name|
        next if new_sizes[name] == 0 || new_sizes[name] == existing_sizes[name]
        [existing_ids[name], new_sizes[name]]
      end
      updates.compact
    end

    # Public: language records that need to be deleted
    def to_delete
      ids = deleted_names.map { |name| existing_ids[name] }

      updated_names.each do |name|
        ids << existing_ids[name] if new_sizes[name] == 0
      end

      ids
    end
  end

  # Internal: the repository this analyzer is for.
  attr_reader :repository

  # Initialize a new language analyzer for a repository.
  #
  # repository - a Repository instance.
  def initialize(repository)
    @repository = repository
  end

  # Public: Analyze a repository's language breakdown.
  #
  # Creates, updates, or removes language analysis entries in the languages
  # table based on data retrieved from linguist. Also sets the primary language
  # for the repository.
  #
  # commit_oid - oid of the commit to analyze
  #              (this is usually the tip of the default branch)
  #
  # Returns nothing.
  def analyze(commit_oid = nil)
    commit_oid ||= repository.default_oid
    if commit_oid == GitHub::NULL_OID || commit_oid.nil?
      clear_analysis
    else
      update_analysis(commit_oid)
    end
  end

  # Public: clear out a repository's language analysis.
  #
  # Deletes language records, resets the repository's primary language, and
  # invalidates caches.
  def clear_analysis
    Language.transaction do
      remove_language_records
      repository.unset_primary_language!
    end
    repository.invalidate_languages_rpc_cache
  end

  # Internal: retrieve the existing language records for this repository
  #
  # Returns an Array of [ [language.id, language_name.name, size], ... ]
  def existing_language_records
    return [] if name_id_id_size_from_languages.empty?

    languages = language_info_by_name_id

    language_names_by_id.each do |ln|
      languages[ln.first] << ln.last
    end

    languages.values.map { |lang| lang.insert(1, lang.delete_at(-1)) }
  end

  def language_info_by_name_id
    name_id_id_size_from_languages.each_with_object({}) do |lang_info, hsh|
      hsh[lang_info[0]] = [lang_info[1], lang_info[-1]]
    end
  end

  def language_names_by_id
    ActiveRecord::Base.connected_to(role: :reading) { LanguageName.ids_and_names(language_info_by_name_id.keys) }
  end

  # Returns an Array of [[language_name_id, language.id language.size], ... ], ordered by descending
  def name_id_id_size_from_languages
    ActiveRecord::Base.connected_to(role: :reading) do
      Language.connection.select_rows(Arel.sql(<<-SQL, repository_id: repository.id))
        SELECT language_name_id, id, size
        FROM languages lang
        WHERE lang.repository_id = :repository_id
      SQL
    end
  end

  # Internal: find or create LanguageName records.
  #
  # names - an Array of language name Strings
  #
  # Returns a Hash of { "Name" => <LanguageName>, ... }
  def find_or_create_language_names(names)
    instances = {}
    names.each do |name|
      instances[name] = LanguageName.lookup_by_name(name)
    end
    instances
  end

  # Internal: remove all analysis records for this repository's analysis
  def remove_language_records
    Language.connection.delete(Arel.sql(<<-SQL, repository_id: repository.id))
      DELETE FROM languages WHERE repository_id = :repository_id
    SQL
  end

  # Internal: update the language analysis for this repository.
  #
  # Performs a language analysis and update the Language records with the
  # results. Compares the newly calculated data against the data in the database
  # and updates, inserts, and deletes records as needed. The repository's
  # primary language is updated as needed.
  def update_analysis(commit_oid)
    new_sizes      = repository.language_size_analysis(commit_oid)
    language_names = find_or_create_language_names(new_sizes.keys)

    diff = Diff.new(new_sizes, existing_language_records, language_names)

    Language.transaction do
      insert_records diff.to_insert
      update_records diff.to_update
      delete_records diff.to_delete
    end

    if diff.to_insert.any? || diff.to_delete.any?
      update_code_scanning_autocodeql_config(diff.new_names, diff.deleted_names)
    end

    set_primary_language new_sizes, language_names
  end

  # Internal: insert language records.
  #
  # to_insert - An Array of [ [ language_name_id, size ], ... ]
  #
  # Returns nothing.
  def insert_records(to_insert)
    return if to_insert.empty?

    to_insert = to_insert.map do |name_id, size|
      [repository.id, name_id, size, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
    end

    GitHub.dogstats.time "language_analyzer.time", tags: ["action:insert"] do
      Language.connection.insert(Arel.sql(<<-SQL, values: Arel::Nodes::ValuesList.new(to_insert)))
        INSERT INTO languages (repository_id, language_name_id, size, created_at, updated_at)
        :values
      SQL
    end
  end

  # Internal: update language records.
  #
  # to_update - An Array of [ [ language_id, size ], ... ]
  #
  # Returns nothing.
  def update_records(to_update)
    return if to_update.empty?

    GitHub.dogstats.time "language_analyzer.time", tags: ["action:update"] do
      to_update.each do |id, size|
        Language.connection.update(Arel.sql(<<-SQL, id: id, size: size))
          UPDATE languages SET size = :size, updated_at = NOW() WHERE id = :id
        SQL
      end
    end
  end

  # Internal: delete language records.
  #
  # to_delete - An Array of [ language_id, ... ]
  #
  # Returns nothing.
  def delete_records(to_delete)
    return if to_delete.empty?

    GitHub.dogstats.time "language_analyzer.time", tags: ["action:analyze_deletes"] do
      Language.connection.delete(Arel.sql(<<-SQL, ids: to_delete))
        DELETE FROM languages WHERE id IN (:ids)
      SQL
    end
  end

  # Internal: set or clear the primary language on the repository.
  #
  # sizes          - a Hash of { "language name" => size, ... }
  # language_names - a Hash of { "language name" => <LanguageName>, ... }
  #
  # Returns nothing.
  def set_primary_language(sizes, language_names)
    primary_language, size = sizes.max_by { |_n, s| s }

    GitHub.dogstats.time "language_analyzer.time", tags: ["action:primary_language_update"] do
      if size && size > 0
        repository.update_primary_language! language_names[primary_language]
      else
        repository.unset_primary_language!
      end
    end
  end

  private

  def update_code_scanning_autocodeql_config(inserted_languages, removed_languages)
    inserted_languages = inserted_languages.map(&:downcase)
    removed_languages = removed_languages.map(&:downcase)

    CodeScanning::AutoCodeqlLanguageUpdateJob.enqueue_if_necessary(repository:, inserted_languages:, removed_languages:)
  end
end
