# typed: true
# frozen_string_literal: true

# Example
# name: Recipe summarizer
# description: Summarizes recipes, tries to reduce the original to 2 steps

# model: azure-openai/gpt-4o
# modelParameters:
#   temperature: 0.5
# messages:
#   - role: user
#     content: |
#       Summarize the given recipe. Try to reduce the original to 2 steps.
#       <recipe>
#       {{recipe}}
#       </recipe>

class GitHubModels::Prompts::ParsedPrompt
  SUPPORTED_ROLES = %w[user assistant tool system developer].freeze

  sig { params(repository: T.nilable(::Repository), path: String, ref: T.nilable(String)).returns(T.nilable(GitHubModels::Prompts::ParsedPrompt)) }
  def self.from_repo(repository, path, ref = nil)
    return nil unless repository
    return nil if path.empty?

    prompt_file = prompt_file_content(repository, ref || repository.default_branch, path)
    return nil unless prompt_file && prompt_file.data
    return nil if prompt_file.binary?

    content = GitHub::Encoding.strip_bom(prompt_file.data.to_s)

    begin
      parsed_content = YAML.safe_load(content)
      return nil if parsed_content.nil?

      messages = parsed_content["messages"]
      metadata = parsed_content.except("messages")

      return nil unless messages.is_a?(Array)

      GitHubModels::Prompts::ParsedPrompt.new(repository:, ref:, path:, metadata:, messages:)
    rescue Psych::SyntaxError, KeyError => e
      # Log the error or handle it gracefully
      GitHub.logger.error("Failed to parse prompt file: #{e.message}")
      nil
    end
  end

  private_class_method def self.prompt_file_content(repository, branch, path)
    head = repository.ref_to_sha(branch)
    return nil if head.nil?

    repository.tree_entry(head, path)
  rescue GitRPC::Error
    nil
  end

  attr_reader :repository, :ref, :path, :data, :messages

  sig do
    params(
      repository: T.nilable(::Repository),
      ref: T.nilable(String),
      path: String,
      metadata: T.nilable(T::Hash[String, T.untyped]),
      messages: T.nilable(T::Array[T::Hash[Symbol, String]]),
    ).void
  end
  def initialize(repository:, ref:, path:, metadata:, messages:)
    @repository = repository
    @ref = ref
    @path = path
    @data = metadata || {}
    @messages = messages&.map do |message|
      message = message.transform_keys(&:to_sym)
      {
        role: message[:role],
        message: message[:content]
      }
    end
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
