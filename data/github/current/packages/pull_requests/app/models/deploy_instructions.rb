# typed: strict
# frozen_string_literal: true

class DeployInstructions
  extend T::Sig
  include GitHub::Memoizer

  TEMPLATE_PATH = ".github/DEPLOY_INSTRUCTIONS.yml"

  sig { returns(Repository) }
  attr_reader :repository

  # repository - The Repository to load deploy instructions for.
  sig { params(repository: Repository).void }
  def initialize(repository:)
    @repository  = repository
  end

  sig { returns(String) }
  def title
    parsed_data["title"] || "Deploy instructions"
  end

  sig { returns(T.nilable(String)) }
  def body
    parsed_data["body"]
  end

  sig { returns(T::Boolean) }
  def valid?
    has_instructions_file?
  end

  sig { returns(T::Boolean) }
  def has_instructions_file?
    template_data.present?
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def parsed_data
    if template_data
      YAML.safe_load(T.must(template_data)) || {}
    else
      {}
    end
  rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError
    {}
  end

  sig { returns(T.nilable(String)) }
  memoize def template_data
    return if repository.nil?
    return if repository.access.broken?

    begin
      repository.tree_entry(repository.default_oid, TEMPLATE_PATH).data
    rescue GitRPC::Error, Repository::CorruptionDetected
      nil
    end
  end
end
