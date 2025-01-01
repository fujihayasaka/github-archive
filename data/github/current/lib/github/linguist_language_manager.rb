# typed: true
# frozen_string_literal: true

require "linguist"

module GitHub

  # The purpose of this class is to keep our `LanguageName` database records in
  # sync with the `Linguist::Language` entries from the Linguist gem. This is
  # accomplished via the `synchronize_languages` method.
  #
  # Example
  #
  #   # do a dry run of the language updates to see what would happen
  #   status = GitHub::LinguistLanguageManager.synchronize_languages(dry_run: true)
  #   puts "Adding #{stats[:added]} languages"
  #   puts "Removing #{stats[:removed]} languages"
  #   puts "Updating #{stats[:updated]} languages"
  #
  #   # and then actually perform the updates
  #   GitHub::LinguistLanguageManager.synchronize_languages(dry_run: false)
  #
  class LinguistLanguageManager
    BATCH_SIZE = 50

    # Convenience method for synchronizing language names.
    def self.synchronize_languages(dry_run: true)
      self.new(dry_run: dry_run).synchronize_languages
    end

    attr_reader :dry_run
    alias :dry_run? :dry_run

    # Just your standard initializer.
    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    # Compare the languages provided by Linguist with the entries in the
    # `language_names` table and take action to bring the `language_names` table
    # in sync with the data in Linguist. This will rename languages, remove
    # languages, and add missing languages.
    #
    # Returns a stats Hash with counts of :added, :removed, :updated languages
    def synchronize_languages
      stats = {
        added:   0,
        removed: 0,
        updated: 0,
      }

      to_add    = linguist_languages.keys - language_names.keys
      to_remove = language_names.keys - linguist_languages.keys
      to_update = linguist_languages.keys & language_names.keys

      stats[:added]   = add_languages(to_add)
      stats[:removed] = remove_languages(to_remove)
      stats[:updated] = update_languages(to_update)

      stats
    end

    # Internal: Iterate through the list of `linguist_ids` and add those
    # Linguist::Language entries to the `language_names` table.
    #
    # Returns the number of languages added
    def add_languages(linguist_ids)
      return if linguist_ids.empty?

      now  = Time.now
      rows = linguist_ids.map do |linguist_id|
        [linguist_languages[linguist_id].name, linguist_id, now, now]
      end

      count = 0
      rows.each_slice(BATCH_SIZE) do |subset|
        count += subset.count
        log("#{dry_run ? "Would insert" : "Inserting"} #{subset.count} language names")

        LanguageName.throttle do
          sql = Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(subset))
            INSERT INTO language_names
            (name, linguist_id, created_at, updated_at) :rows
          SQL
          LanguageName.connection.insert(sql) unless dry_run?
        end
      end
      count
    end

    # Internal: Iterate through the list of `linguist_ids` and mark the
    # LanguageName entries as "removed" for any LanguageName that does not have
    # a corresponding Linguist::Language.
    #
    # Returns the number of languages removed
    def remove_languages(linguist_ids)
      return if linguist_ids.empty?

      count = 0
      ids   = language_names.values_at(*linguist_ids).flatten.map(&:id)

      ids.each_slice(BATCH_SIZE) do |subset|
        count += subset.count
        log("#{dry_run ? "Would mark" : "Marking"} #{subset.count} language names as removed")

        LanguageName.throttle do
          unless dry_run?
            sql = LanguageName.connection.update(Arel.sql(<<-SQL, ids: ids))
              UPDATE language_names
              SET linguist_id = NULL
              WHERE id in (:ids)
            SQL
          end
        end
      end
      count
    end

    # Internal: Iterate through the list of `linguist_ids` and update the
    # LanguageName entries where the name differs from the Linguist::Language
    # name.
    #
    # Returns the number of languages updated
    def update_languages(linguist_ids)
      return if linguist_ids.empty?

      to_update = linguist_ids.map do |id|
        linguist_language = linguist_languages[id]
        language_name     = language_names[id]

        if language_name.is_a?(Array)
          verify_language_and_aliases(linguist_language, language_name)
        else
          verify_language(linguist_language, language_name)
        end
      end
      to_update.flatten!
      to_update.compact!

      log("#{dry_run ? "Would update" : "Updating"} #{to_update.count} language names with new Linguist names")

      unless dry_run?
        LanguageName.throttle do
          to_update.each do |language_name|
            language_name.save!
          end
        end
      end
      to_update.count
    end

    # Internal: Compares the `name` found in the Linguist::Language and in the
    # LanguageName. If the values differ, then the LanguageName is updated with
    # the new value (but not saved to the database) and returned by this method.
    # If the values are the same, then `nil` is returned.
    #
    # Returns the LanguageName or `nil`
    def verify_language(linguist_language, language_name)
      return if linguist_language.name == language_name.name
      language_name.name = linguist_language.name
      language_name
    end

    # Internal: Some LanguageName entries are actually an alias name to another
    # Linguist::Language. For example, we have both "Component Pascal" and
    # "Delphi" in the `language_names` table, and both have a `linguist_id` of
    # 67. The first is the real language name, and the second is an alias for
    # the first.
    #
    # This method here looks to see if a LanguageName still exists accounting
    # for aliases. The first LanguageName entry will be renamed if needed, and
    # subsequent LanguageName entires are treated as aliases to the canonical
    # name.
    #
    # Returns an Array of LanguageName instances that need to be updated in MySQL
    def verify_language_and_aliases(linguist_language, language_name_array)
      linguist_name    = linguist_language.name
      linguist_aliases = linguist_language.aliases

      results = []
      language_name_array.each do |language_name|
        name = language_name.name
        next if linguist_name == name
        next if linguist_aliases.include?(name.downcase)

        language_name.linguist_id = nil
        results << language_name
      end

      results.compact!
      results
    end

    # Internal: Returns a Hash of all `LanguageName` records keyed by the
    # `linguist_id`. If a `LanguageName` does not have a corresponding Linguist
    # entry, then it is not included in the returned Hash. If a `linguist_id`
    # has more than one `LanguageName` associated with it, then the Hash entry
    # will be an Array of those `LanguageName` records.
    #
    # Returns a Hash of LanguageName entries
    def language_names
      return @language_names if defined? @language_names
      @language_names = {}

      LanguageName.all.each do |language_name|
        linguist_id = language_name.linguist_id
        next if linguist_id.nil?

        if @language_names.key? linguist_id
          @language_names[linguist_id] = Array(@language_names[linguist_id]) << language_name
        else
          @language_names[linguist_id] = language_name
        end
      end

      @language_names
    end

    # Internal: Returns a Hash of all `Linguist::Language` instances keyed by
    # the `linguist_id`.
    def linguist_languages
      return @linguist_languages if defined? @linguist_languages
      @linguist_languages = {}

      Linguist::Language.all.each do |language|
        @linguist_languages[language.language_id] = language
      end

      @linguist_languages
    end

    # Internal: Write a log message - send to STDOUT if not in test
    def log(message)
      Rails.logger.debug message
      return if Rails.env.test?
      puts "[#{Time.now.iso8601.sub(/-\d+:\d+$/, '')}] #{message}"
    end
  end
end
