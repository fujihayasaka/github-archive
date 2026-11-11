# typed: true
# frozen_string_literal: true

class DiscussionTemplates
  TEMPLATES_DIRECTORY  = ".github/DISCUSSION_TEMPLATE"
  FILE_EXTENSION_REGEX = /\A\.(yml|yaml)\z/i

  sig { returns Repository }
  attr_reader :repository

  sig { params(repository: Repository).void }
  def initialize(repository)
    @repository = repository
  end

  # Public: Is a given string a valid path to a discussion template?
  #
  # string - A string file path.
  #
  # Returns a Boolean.
  sig { params(string: T.nilable(String)).returns(T::Boolean) }
  def self.valid_path?(string)
    return false unless string.present?
    return false unless string.starts_with?(TEMPLATES_DIRECTORY)
    FILE_EXTENSION_REGEX.match?(File.extname(string))
  end

  # Public: Get the template for a given category slug, if one exists.
  #
  # name - The String category slug to find a template for.
  #
  # Returns a DiscussionTemplate|nil.
  sig { params(slug: T.nilable(String)).returns(T.nilable(DiscussionTemplate)) }
  def for_slug(slug)
    return unless slug.present?
    valid_templates.find { |template| template.category_slug == slug }
  end

  sig { params(name: T.nilable(String)).returns(T.nilable(DiscussionTemplate)) }
  def [](name)
    return unless name.present?
    templates_by_filename[name]
  end

  sig { returns(T::Boolean) }
  def any?
    valid_templates.any?
  end

  sig { returns(T::Array[DiscussionTemplate]) }
  def valid_templates
    @valid_templates ||= templates.select(&:valid?)
  end

  sig { returns(T::Array[DiscussionTemplate]) }
  def templates
    @templates ||= templates_by_filename.values
  end

  private

  sig { returns T::Hash[String, DiscussionTemplate] }
  def templates_by_filename
    @templates_by_name ||= template_tree_entries.each_with_object({}) do |tree_entry, result|
      next unless FILE_EXTENSION_REGEX.match?(File.extname(tree_entry.name))
      template = DiscussionTemplate.from_tree_entry(tree_entry)
      result[template.filename] = template
    end
  end

  def template_tree_entries
    return [] if repository.blank?
    return [] if repository.access.broken?

    begin
      directory = repository.directory(repository.default_oid, TEMPLATES_DIRECTORY)
      directory&.tree_entries || []
    rescue GitRPC::Error, Repository::CorruptionDetected
      []
    end
  end
end
