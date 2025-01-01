# typed: false
# frozen_string_literal: true

# Represents a normative code of conduct (e.g., Contributor Covenant v1.4)
# and it's metadata (not associated with a Repository)
# For a repository's codes of conduct, see repository_code_of_conduct.rb
class CodeOfConduct < Coconductor::CodeOfConduct
  include GitHub::Relay::GlobalIdentification

  # Recomended families to display on the picker and provide prefferential
  # status when calculating the community profile
  RECOMMENDED = %w(
    django
    contributor-covenant
  )

  # Family => description for use in the code of conduct picker
  DESCRIPTIONS = {
    "contributor-covenant" => "Recommended for projects of all sizes",
    "django" => "Suitable for large communities and events",
  }

  # Relay Global Identification
  alias id key

  # Detect a repository's code of conduct
  #
  # repo - the Repository object
  #
  # Returns the detected CodeOfConduct or nil if no code of conduct is detected
  def self.detect(repo)
    coc = repo.code_of_conduct
    coc unless coc.none?
  end

  # Utility method to return a code of conduct object by a specified key
  def self.find_by_key(key)  # rubocop:disable GitHub/FindByDef
    super(key.to_s.gsub("_", "-"))
  end

  def self.recommended
    @recommended ||= latest.select(&:recommended?).sort_by(&:name).reverse
  end

  class << self
    alias find find_by_key
  end

  def recommended?
    RECOMMENDED.include?(family)
  end

  def description
    DESCRIPTIONS[family]
  end

  # Backwards compatabailize the key and name by removing the version to avoid breaking API changes
  # Fallback to converting the name to a key like value if a family doesn't exist. Our APIs expect
  # this value to be non-null. If a code of conduct file is blank, then family is nil.
  # TODO: Remove this and announce the change so the API returns hyphenated values with versions
  #       See https://git.io/fh2wn.
  def legacy_key
    family ? family.gsub("-", "_") : "none"
  end
  alias_method :name, :name_without_version

  # Given a hash of field keys => values, compiles the repo-specific
  # code of conduct to be committed
  # See Coconductor::Field.all.map(&:key) for a list of valid fields
  def generate(values)
    generated = content.dup
    values = values.stringify_keys

    fields.each do |field|
      value = maybe_linkify_url(field, values[field.key.to_s])
      generated.gsub!(field.raw_text, value) if value
    end

    generated
  end

  # Used to generate etags for the API
  def last_modified_at
    Coconductor::VERSION
  end

  # Codes of Conduct do not have HTML views
  def url; nil; end
  def path; nil; end

  private

  # Converts the value of a field into a Markdown link if
  #   (A) the field is intended to be a URL, and
  #   (B) the value is a URL
  # Returns the linkified value or the original value
  def maybe_linkify_url(field, value)
    return value unless field.key.start_with?("link_to_") && value && value.start_with?("http")
    "[#{field.label.gsub('Link to ', '').capitalize}](#{value})"
  end
end
