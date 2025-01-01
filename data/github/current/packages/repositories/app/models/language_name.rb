# typed: true
# frozen_string_literal: true

class LanguageName < ApplicationRecord::Domain::LanguageNames
  extend T::Sig

  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  SYMBOL_REPLACEMENTS = {
    "#" => "sharp",
    "*" => "star",
    "+" => "plus",
    "." => "dot",
  }.freeze

  validates_presence_of :name
  validates :name, unicode3: true

  has_many :integration_listing_language_names
  has_many :integration_listings, through: :integration_listing_language_names, source: :integration_listing

  sig { params(name: String).returns(String) }
  def self.clean_name(name)
    result = name.downcase

    SYMBOL_REPLACEMENTS.each do |symbol, replacement|
      result = result.gsub(symbol, replacement)
    end

    result
      .gsub(/[^a-z0-9]/, "_")
      .gsub(/_+/, "_")
      .gsub(/\A_|_\z/, "")
  end

  # Find language name by Linguist alias
  def self.find_by_alias(lang_alias)  # rubocop:disable GitHub/FindByDef
    if lang = Linguist::Language.find_by_alias(lang_alias)
      find_by(name: lang.name)
    end
  end

  def self.sorted_rankings
    query = {
      aggregations: {
        language: {
          terms: { field: "language" },
        },
      },
    }

    results = Elastomer::Indexes::Repos.new.search(query,
      size: 0,
    )

    results["aggregations"]["language"]["buckets"].map do |term|
      [term["key"], term["doc_count"]]
    end
  end

  # All languages, sorted by name
  def self.all_sorted
    @all_sorted ||= order("name ASC").all
  end

  # Given a language `name` String find the LanguageName row. If we do not have
  # a row in the database, then go ahead and create the LanguageName from the
  # Linguist::Language information.
  #
  # NOTE - this method needs to be removed from the application. Instead, we
  # should create a row in the `language_names` table for each Linguist language
  # we support and do away with this "find or create" nonsense. That will be a
  # follow-on pull request.
  #
  # Returns a LanguageName or `nil`
  def self.lookup_by_name(name)
    if language_name = self.find_by(name: name) ||
                       self.find_by_alias(name)
      language_name

    elsif linguist = Linguist::Language.find_by_name(name) ||
                     Linguist::Language.find_by_alias(name)
      LanguageName.create! \
        name:        linguist.name,
        linguist_id: linguist.language_id
    end
  end

  def self.lookup_by_names(names)
    names.map { |name| self.lookup_by_name(name) }
  end

  sig { returns(T.nilable(String)) }
  def to_s
    name
  end

  sig { returns(String) }
  def clean_name
    self.class.clean_name(name.to_s)
  end

  # Public: Returns the Linguist::Language for this LanguageName. Returns `nil`
  # if this LanguageName cannot be mapped to a Linguist::Language.
  def language
    return if linguist_id.nil?
    Linguist::Language.find_by_id(linguist_id)
  end

  # Public: Provides access to the Linguist language name and falls back to the
  # `name` from the database if this LanguageName cannot be mapped to a
  # Linguist::Language.
  #
  # Returns a name String.
  def linguist_name
    language && language.name || name
  end

  def platform_type_name
    "Language"
  end

  # Returns an Array of [[language_name.id, language_name.name], ... ]
  def self.ids_and_names(ids)
    return [] unless ids && ids.any?
    LanguageName.connection.select_rows(Arel.sql(<<-SQL, language_name_ids: ids))
      SELECT language_names.id language_name_id, language_names.name name
      FROM language_names
      WHERE id IN (:language_name_ids)
    SQL
  end
end
