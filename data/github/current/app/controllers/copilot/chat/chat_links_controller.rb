# typed: true
# frozen_string_literal: true

class Copilot::Chat::ChatLinksController < Copilot::Chat::AbstractChatController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    return head :not_found unless chat_links_enabled?
    return head :not_found unless chat_link_item
    return head :not_found unless chat_link_item&.readable_by?(current_user)

    render json: json_payload(chat_link_item)
  end

  private

  def json_payload(item)
    case item
    when Issue
      issue_payload(item)
    when Discussion
      discussion_payload(item)
    when PullRequest
      pull_request_payload(item)
    when ::Figma::File
      figma_payload(item)
    end
  end

  def issue_payload(item)
    {
      type: "issue",
      id: item.id,
      number: item.number,
      repository: repository_payload(item.repository),
      title: item.title,
      body: item.body,
      state: item.state_reason_not_planned? ? "not_planned" : item.state,
      url: item.url,
      assignees: item.assignees,
    }
  end

  def discussion_payload(item)
    {
      type: "discussion",
      id: item.id,
      number: item.number,
      title: item.title,
      body: item.body,
      user: user_payload(item.user),
      state: item.state,
      url: item.url,
      authorLogin: item.user&.display_login,
      repository: repository_payload(item.repository)
    }
  end

  def pull_request_payload(item)
    {
      type: "pull_request",
      title: item.title,
      url: item.url,
      authorLogin: item.user&.display_login,
      repository: repository_payload(item.repository)
    }
  end

  def repository_payload(repository)
    {
      id: repository&.id,
      name: repository&.name,
      owner: repository&.owner&.display_login,
    }
  end

  def user_payload(user)
    {
      login: user&.display_login,
    }
  end

  def figma_payload(file)
    {
      type: "figma",
      title: file.name,
      id: file.key,
      url: params[:item_url],
      thumbnailUrl: file.thumbnail_url,
      fullImageUrl: file.full_image_url,
    }
  end

  sig { returns T.nilable(T.any(Issue, Discussion, PullRequest, ::Figma::File)) }
  memoize def chat_link_item
    return unless item_url

    if figma_url?
      figma_file
    elsif item_url&.include?("/issues/")
      _, issue_number = item_url&.split("/issues/")

      repository&.issues&.find_by(number: issue_number)
    elsif item_url&.include?("/pull/")
      _, pr_number = item_url&.split("/pull/")

      issue = repository&.issues&.find_by(number: pr_number)
      issue&.pull_request
    elsif item_url&.include?("/discussions/")
      _, discussion_number = item_url&.split("/discussions/")

      repository&.discussions&.find_by(number: discussion_number)
    end
  end

  sig { returns T.nilable(Repository) }
  memoize def repository
    repo_name_with_owner, _ = item_url&.split(%r{/(issues|pull|discussions)/})
    Repository.with_name_with_owner(repo_name_with_owner)
  end

  sig { returns T.nilable(::Figma::File) }
  memoize def figma_file
    return unless figma_url?

    GitHub.figma_client.get_file(params[:item_url])
  rescue ::Figma::APIError => e
    Rails.logger.error("Failed to fetch Figma file: #{e}")
    nil
  end

  ALLOWED_FIGMA_HOSTS = ["figma.com", "www.figma.com"].freeze

  sig { returns(T.nilable(T::Boolean)) }
  memoize def figma_url?
    return false unless params[:item_url]

    uri = URI.parse(params[:item_url])
    ALLOWED_FIGMA_HOSTS.include?(uri.host)
  end

  sig { returns T.nilable(String) }
  def item_url
    return nil unless params[:item_url]

    uri = URI.parse(params[:item_url])
    T.must(uri.path)[1..-1]
  end

  sig { returns(T::Boolean) }
  def chat_links_enabled?
    current_user.feature_enabled?(:copilot_ui_refs)
  end

  def target_for_conditional_access
    chat_link_item&.target_for_conditional_access
  end

  def resource_for_conditional_access
    chat_link_item || :no_resource_for_conditional_access # rubocop:todo GitHub/SpecifyResourceForConditionalAccess
  end
end
