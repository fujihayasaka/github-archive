# typed: true
# frozen_string_literal: true

# Example
# ---
# name: Recipe summarizer
# description: Summarizes recipes, tries to reduce the original to 2 steps

# model: azure-openai/gpt-4o
# modelParameters:
#   temperature: 0.5
# ---
# user:
# Summarize the given recipe. Try to reduce the original to 2 steps.
# <recipe>
# {{recipe}}
# </recipe>

class GitHubModels::Prompts::ParsedPrompt
  Messages = T.type_alias { T::Array[GitHubModels::Prompts::Message] }

  SUPPORTED_ROLES = %w[user assistant tool system developer].freeze
  PROMPT_SEPARATOR_REGEX = /^\s*#?\s*(#{SUPPORTED_ROLES.join('|')})\s*:\s*$/im

  sig { params(repository: T.nilable(::Repository), path: String, ref: T.nilable(String)).returns(T.nilable(GitHubModels::Prompts::ParsedPrompt)) }
  def self.from_repo(repository, path, ref = nil)
    return nil unless repository
    return nil if path.empty?

    prompt_file = prompt_file_content(repository, ref || repository.default_branch, path)
    return nil unless prompt_file && prompt_file.data
    return nil if prompt_file.binary?

    content = GitHub::Encoding.strip_bom(prompt_file.data.to_s)

    metadata, messages = self.parse_from_md(content)
    GitHubModels::Prompts::ParsedPrompt.new(repository:, ref:, path:, metadata:, messages:)
  end

  private_class_method def self.prompt_file_content(repository, branch, path)
    head = repository.ref_to_sha(branch)
    return nil if head.nil?

    repository.tree_entry(head, path)
  rescue GitRPC::Error
    nil
  end

  sig { params(content: String).returns([T.nilable(T::Hash[String, T.untyped]), Messages]) }
  def self.parse_from_md(content)
    fm = GitHubModels::Prompts::FrontMatter.new(content)
    metadata = fm.metadata
    messages = parse_messages(fm.content)

    [metadata, messages]
  end

  sig { params(content: String).returns(Messages) }
  def self.parse_messages(content)
    # Given content like
    #
    # <role>:
    #   some prompt
    # <another-role>:
    #   some other prompt
    #
    # or
    #
    # <some prompt
    #
    # parse this into an array of prompt messages
    segments = content.split(PROMPT_SEPARATOR_REGEX)
    messages = T.let([], Messages)

    # The first segment is always the content before the first role
    # if it exists, otherwise it's the entire content with no roles
    initial_content = segments.shift
    if segments.empty?
      messages << GitHubModels::Prompts::Message.new(role: "user", content: T.must(initial_content&.strip))
      return messages
    end

    # Now we have alternating role, content, role, content, etc.
    # so we can zip them together and create the messages
    roles = segments.select.with_index { |_, i| i.even? }
    contents = segments.select.with_index { |_, i| i.odd? }

    roles.zip(contents).each do |role, content|
      messages << GitHubModels::Prompts::Message.new(role: role.downcase, content: content.strip)
    end

    messages
  end

  attr_reader :repository, :ref, :path, :data, :messages

  sig do
    params(
      repository: T.nilable(::Repository),
      ref: T.nilable(String),
      path: String,
      metadata: T.nilable(T::Hash[String, T.untyped]),
      messages: Messages,
    ).void
  end
  def initialize(repository:, ref:, path:, metadata:, messages:)
    @repository = repository
    @ref = ref
    @path = path
    @data = metadata || {}
    @messages = messages
  end

  sig { returns(String) }
  def name
    @data["name"] || File.basename(@path)
  end

  sig { returns(T.nilable(String)) }
  def description
    @data["description"]
  end

  sig { returns(T.nilable(String)) }
  def model_name
    @data["model"]
  end
end
