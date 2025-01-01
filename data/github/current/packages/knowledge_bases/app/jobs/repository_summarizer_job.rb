# typed: true
# frozen_string_literal: true

class RepositorySummarizerJob < ApplicationJob
  include Copilot::Prompt::Tokens
  queue_as :repository_summarizer
  retry_on_dirty_exit

  MODEL = "gpt-4o-mini".freeze
  EMBEDDING_MODEL = "text-embedding-3-small".freeze
  # 4o-mini has a context window limit of 128k tokens
  # However, we have an internal limit of ~12k tokens
  # context window includes both input and output tokens
  # for now, lets allot 10k tokens for input
  # TODO BEFORE MERGE: increase this limit to 10k after obtaining max prompt token approval
  MAX_INPUT_TOKENS = 7000.freeze

  def perform(repo, user, kb_id)
    return unless user.feature_enabled?(:copilot_chat_magic_kbs)

    file_summaries = use_file_contents(user) ? summary_by_file_contents(repo, user) : summary_by_file_names(repo, user)

    if file_summaries.present?
      repo_description = repo_summary(file_summaries, user)
      embedding = embed_repo_summary(kb_id, user, repo_description)
      store_repo_summary(kb_id, user, repo.id, repo_description, embedding)
    else
      GitHub.logger.info("RepoSummarizerJob: No file summaries.")
    end
  end

  def summary_by_file_names(repo, user)
    oid = repo.default_oid
    paths = repo.tree_file_list(oid)
    prompt = repo_filename_prompt(repo, paths)
    file_name_prompt_token_count = count_tokens(prompt)

    if file_name_prompt_token_count > MAX_INPUT_TOKENS
      prompt = truncate_prompt(prompt)
      GitHub.logger.info("RepoSummarizerJob: Filename prompt token limit exceeded. Token count: #{file_name_prompt_token_count}.")
    end

    begin
      result = api(user).create_chat_completion(
        model: RepositorySummarizerJob::MODEL,
        messages: [role: "user", content: prompt],
        max_tokens: 1000,
        temperature: 0.2,
        stop: []
      )

      result.dig("choices", 0, "message", "content")
    rescue CopilotAPI::RateLimitError => e
      GitHub.logger.info("RepoSummarizerJob: Rate limit exceeded: #{e}.")
    rescue CopilotAPI::EntityTooLargeError => e
      GitHub.logger.info("RepoSummarizerJob: Entity too large: #{e}. Token count: #{file_name_prompt_token_count}.")
    rescue CopilotAPI::RequestError => e
      GitHub.logger.info("RepoSummarizerJob: Request error: #{e}. Token count: #{file_name_prompt_token_count}.")
    rescue CopilotAPI::Error => e
      GitHub.logger.info("RepoSummarizerJob: Failed to summarize file names: #{e}. Token count: #{file_name_prompt_token_count}.")
    end
  end

  def summary_by_file_contents(repo, user)
    # get repo contents (md, and mdx files)
    markdown_files = GitHub::Spokes::Client::Spokesd.instance.get_all_filepaths_from_repo(repo.id, "refs/heads/#{repo.default_branch}", file_extensions: [".md", ".mdx"])
    file_summaries = []
    markdown_files.map do |filepath|
      blob = repo.blob(repo.default_oid, filepath)
      contents = blob.data

      if contents.blank?
        GitHub.logger.info("RepoSummarizerJob: No file content.")
        next
      end

      file_content_prompt = file_content_prompt(filepath, contents)
      file_content_token_count = count_tokens(file_content_prompt)

      # truncate file content if it exceeds the token limit
      # TODO: split file content into chunks to be analyzed separately if token count exceeds limit
      if file_content_token_count > MAX_INPUT_TOKENS
        file_content_prompt = truncate_prompt(file_content_prompt)
        GitHub.logger.info("RepoSummarizerJob: File contents exceed limit. Token count: #{file_content_token_count}.")
      end

      begin
        result = api(user).create_chat_completion(
          model: RepositorySummarizerJob::MODEL,
          messages: [role: "user", content: file_content_prompt],
          max_tokens: 500,
          temperature: 0.2,
          stop: []
        )

        description = result.dig("choices", 0, "message", "content")
        file_summaries << description

      rescue CopilotAPI::RateLimitError => e
        GitHub.logger.info("RepoSummarizerJob: Rate limit exceeded: #{e}.")
      rescue CopilotAPI::EntityTooLargeError => e
        GitHub.logger.info("RepoSummarizerJob: Entity too large: #{e}. Token count: #{file_content_token_count}.")
      rescue CopilotAPI::RequestError => e
        GitHub.logger.info("RepoSummarizerJob: Request error: #{e}. Token count: #{file_content_token_count}.")
      rescue CopilotAPI::Error => e
        GitHub.logger.info("RepoSummarizerJob: Failed to summarize file: #{e}. Token count: #{file_content_token_count}.")
      end
    end
    file_summaries
  end

  def repo_summary(file_summaries, user)
    repo_prompt = repo_summary_prompt(file_summaries)
    repo_prompt_token_count = count_tokens(repo_prompt)

    # truncate summaries for now
    # TODO: split summaries into chunks to be analyzed separately if token count exceeds limit
    if repo_prompt_token_count > MAX_INPUT_TOKENS
      repo_prompt = truncate_prompt(repo_prompt)
      GitHub.logger.info("RepoSummarizerJob: Repo summary prompt token limit exceeded. Token count: #{repo_prompt_token_count}.")
    end

    begin
      result = api(user).create_chat_completion(
        model: RepositorySummarizerJob::MODEL,
        messages: [role: "user", content: repo_prompt],
        max_tokens: 1000,
        temperature: 0.2,
        stop: []
      )

      result.dig("choices", 0, "message", "content")
    rescue CopilotAPI::RateLimitError => e
      GitHub.logger.info("RepoSummarizerJob: Rate limit exceeded: #{e}.")
      e
    rescue CopilotAPI::EntityTooLargeError => e
      GitHub.logger.info("RepoSummarizerJob: Entity too large: #{e}. Token count: #{repo_prompt_token_count}.")
      e
    rescue CopilotAPI::RequestError => e
      GitHub.logger.info("RepoSummarizerJob: Request error: #{e}. Token count: #{repo_prompt_token_count}.")
      e
    rescue CopilotAPI::Error => e
      GitHub.logger.info("RepoSummarizerJob: Failed to summarize repo: #{e}. Token count: #{repo_prompt_token_count}.")
      e
    end
  end

  def store_repo_summary(kb_id, user, repo_id, repo_description, embedding)
    api(user).update_knowledge_base_repo_description(kb_id, repo_id, repo_description, embedding)
  end

  def embed_repo_summary(kb_id, user, repo_description)
    begin
      result = api(user).create_embedding(model: EMBEDDING_MODEL, input: repo_description)
      result.dig("data", 0, "embedding")
    rescue CopilotAPI::Error => e
      GitHub.logger.info("RepoSummarizerJob: Failed to embed repo summary: #{e}.")
    end
  end

  def api(user)
    @_api ||= user.copilot_api(integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID)
  end

  def repo_filename_prompt(repo, paths)
    "Analyze the following file names and provide a structured summary of the repository #{repo.name_with_display_owner}. Note the most important topics and reoccurring themes. Be concise. Avoid editorializing or fluff words. Get to the point as much as possible.

    Here are the file names in the repository ` + #{repo.name} + `: #{paths}"
  end

  def file_content_prompt(filepath, contents)
    "Analyze the following file content and provide a structured summary of the file. Note the most important topics and reoccurring themes. Be concise and avoid summarizing the entire file. Avoid editorializing or fluff words. Get to the point as much as possible.

    Here's the content of the file '` + #{filepath} + `' to analyze: #{contents}"
  end

  def repo_summary_prompt(file_summaries)
    "You are tasked with creating a comprehensive and cohesive summary of a repository based on the summaries of its individual files.

    Your goal is to:
    1. Identify the main themes and key points across all the file summaries, focusing on the most frequent and important topics.
    2. Synthesize these points into a logical and coherent narrative about the entire repository.

    Include 10-20 topics, do not include any metadata about count or importance.

    Please provide a well-structured, paragraph-form summary that captures the essence of the entire repository based on these file summaries. The summary should be understandable to someone who hasn't read the original files.

    Avoid editorializing or fluff words. Be concise and get to the point as much as possible.

    Here is a list of the file summaries to analyze: #{file_summaries}."
  end

  def truncate_prompt(prompt)
    prompt.first(MAX_INPUT_TOKENS * Copilot::Prompt::Tokens::CHARACTERS_PER_TOKEN)
  end

  def use_file_contents(user)
    user.feature_enabled?(:copilot_chat_magic_kbs_file_content_summarizer)
  end
end
