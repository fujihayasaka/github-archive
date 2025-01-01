# typed: true
# frozen_string_literal: true

class Copilot::Chat::ContextController < AbstractRepositoryController

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:show],
  )

  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:show]

  def show
    return render json: nil unless rails_path
    return render json: nil unless parsed_uri

    controller = rails_path[:controller]
    response = {}

    case controller
    when "files"
      ref, path = ref_sha_path_extractor.call(rails_path[:name]) if rails_path.has_key?(:name)
      response = helpers.repo_props(repo: current_repository, ref_name: ref)
      if response
        response[:type] = "repository"
        response[:path] = path || "" # If we're on a repo root page, there is no path param
      end
    when "blob"
      if rails_path.has_key?(:name)
        @branch, @path = ref_sha_path_extractor.call(rails_path[:name])
      end
      response = snippet_range ? snippet_props : blob_props
    when "compare"
      range = rails_path[:range]
      return render(json: nil) unless range

      comparison = GitHub::Comparison.from_range_or_ref(
        current_repository,
        range,
        limit: 1,
        user: current_user,
      )
      response = comparison_props(comparison)
    when "actions/job"
      response = {
        type: "job",
        repoId: current_repository.id,
        repoOwner: owner.display_login,
        repoName: current_repository.name,
        job_id: rails_path[:job_id].to_i,
      }
    when "pull_requests"
      response = pull_request_path_props
    when "issues"
      response = issue_props
    when "repos/code_scanning"
      response = code_scanning_alert_props
    when "repos/secret_scanning/react_alerts"
      response = secret_scanning_alert_props
    when "repos/dependabot_alerts"
      response = dependabot_alert_props
    when "discussions"
      response = discussions_props
    when "releases"
      response = release_props
    when "commit"
      response = commit_props
    when "workspace_editor/index"
      response = workspace_editor_props
    else
      return render json: nil
    end

    render json: response
  end

  private

  memoize def rails_path
    Rails.application.routes.recognize_path params[:url]
  rescue ActionController::RoutingError
    nil
  end

  memoize def parsed_uri
    URI(params[:url])
  rescue URI::Error
    nil
  end

  def commit_props
    return {} unless rails_path[:controller] == "commit" && rails_path[:action] == "show" && rails_path[:name].present?

    commit_sha = rails_path[:name]

    # repository.commits.find requires a full SHA
    if commit_sha && commit_sha.size != 40
      commit_sha = current_repository.ref_to_sha(commit_sha)
    end

    commit = current_repository.commits.find(commit_sha)
    return {} unless commit

    # The keys must match the type defined in CopilotChatReference or the context will be ignored silently
    # ui/packages/copilot-chat/utils/copilot-chat-types.ts
    author = commit.author
    result = {
      type: "commit",
      oid: commit.oid,
      message: commit.message,
      permalink: commit.permalink,
      author: {
        name: author&.name,
        email: author&.email,
        login: author&.display_login,
      },
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
    result
  end

  def blob_props(url = parsed_uri)
    {
      type: "file",
      url: url,
      path: @path,
      repoID: current_repository.id,
      repoOwner: owner.display_login,
      repoName: current_repository.name,
      ref: @branch,
      commitOID: current_repository.ref_to_sha(@branch),
    }
  end

  sig { params(comparison: GitHub::Comparison).returns(T::Hash[Symbol, T.untyped]) }
  def comparison_props(comparison)
    {
      type: "tree-comparison",
      baseRevision: comparison.base_sha,
      headRevision: comparison.head_sha,
      headRepoId: comparison.head_repo.id,
      baseRepoId: comparison.base_repo.id,
    }
  end

  SNIPPET_RANGE = /\AL(?<start>\d+)(-L(?<end>\d+))?\z/
  # Returns a hash with the start and end line numbers, or nil if the fragment is not a range
  memoize def snippet_range
    # Parse the hash to get the start and end line numbers
    # Hash could be "L1" or "L1-L3", for example
    matches = parsed_uri.fragment&.match(SNIPPET_RANGE)
    return nil unless matches && matches[:start]

    start_line = matches[:start].to_i
    end_line = matches[:end] ? matches[:end].to_i : start_line
    {
      start: start_line,
      end: end_line,
    }
  end

  def snippet_props
    {
      type: "snippet",
      url: parsed_uri,
      path: @path,
      repoID: current_repository.id,
      repoOwner: owner.display_login,
      repoName: current_repository.name,
      ref: @branch,
      commitOID: current_repository.ref_to_sha(@branch),
      range: snippet_range,
    }
  end

  def issue_props
    rails_path[:controller] == "issues" && rails_path[:action] == "show" && rails_path[:id].present?

    # Checks if request is from pull requests page
    # and if so, we return the pull request type
    if rails_path[:pulls_only]
      return {
          type: "pull-requests",
          repository: {
          id: current_repository.id,
          name: current_repository.name,
          owner: owner.display_login,
        }
      }
    end

    issue = Issue.find_by(repository: current_repository, number: rails_path[:id]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    #Returns type issues if request is from issues page
    # and the issue is not found
    return {
      type: "issues",
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    } unless issue

    {
      type: "issue",
      id: issue.id,
      number: issue.number,
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
  end

  def code_scanning_alert_props
    rails_path[:controller] == "repos/code_scanning" && rails_path[:action] == "show" && rails_path[:number].present?

    {
      type: "code-scanning-alert",
      number: rails_path[:number].to_i,
      ref: current_repository.default_branch_ref&.qualified_name,
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
  end

  def secret_scanning_alert_props
    return {} unless rails_path[:controller] == "repos/secret_scanning/react_alerts" && rails_path[:action] == "show" && rails_path[:id].present?

    {
      type: "secret-scanning-alert",
      number: rails_path[:id].to_i,
      ref: current_repository.default_branch_ref&.qualified_name,
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
  end

  def dependabot_alert_props
    rails_path[:controller] == "repos/dependabot_alerts" && rails_path[:action] == "show" && rails_path[:number].present?
    {
      type: "dependabot-alert",
      number: rails_path[:number].to_i,
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
  end

  def release_props
    return {} unless rails_path[:controller] == "releases" && rails_path[:action] == "show" && rails_path[:name].present?


    release = Releases::Public.load_by_tag(current_repository.id, rails_path[:name])
    return {} unless release

    # The keys must match the type defined in CopilotChatReference or the context will be ignored silently
    # ui/packages/copilot-chat/utils/copilot-chat-types.ts
    {
      type: "release",
      id: release.id,
      tagName: release.tag_name,
      isDraft: release.draft?,
      isPrerelease: release.prerelease?,
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      },
    }
  end

  def pull_request_path_props
    return {} unless (rails_path[:controller] == "pull_requests" && %w(show commits files checks).include?(rails_path[:action]) && rails_path[:id].present?) ||
    valid_workspace_editor_request?
    # Note: this action shows a specific commit in the context of a pull request. In this case, it makes more sense to return the commit details.
    # If no commit is found, we fallback to the pull request details.
    if rails_path[:tab] == "commits" && rails_path[:range].present?
      commit_sha = rails_path[:range]
      begin
        commit = current_repository.commits.find(commit_sha)
      rescue RepositoryObjectsCollection::InvalidObjectId
        commit = nil
      end

      return {
        type: "commit",
        oid: commit.oid,
        repository: {
          id: current_repository.id,
          name: current_repository.name,
          owner: owner.display_login,
        }
      } if commit.present?
    end

    pull_request = T.let(current_repository.issues.find_by_number(rails_path[:id])&.pull_request, T.nilable(PullRequest)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return {} unless pull_request

    comparison = pull_request.historical_comparison
    reference = {
      type: "pull-request",
      number: pull_request.number,
      baseRevision: comparison.base_sha,
      headRevision: comparison.head_sha,
      headRepoId: comparison.head_repo.id,
      baseRepoId: comparison.base_repo.id,
      repository: {
        id: current_repository.id,
        nwo: current_repository.name_with_display_owner,
      }
    }

    if FeatureFlag.vexi.enabled?(:copilot_task_oriented_assistive_prompts, current_user, default: false)
      reference[:persona] = if pull_request.user == current_user
        "author"
      elsif pull_request.review_requests_for(current_user, requests: pull_request.review_requests).any?
        # If there are any review requests (pending or not) for the current user or owning teams, they are a reviewer
        # Note that this only applies to actual review requests, not suggestions. Typically draft PRs do not yet have reviewers unless the author explicit adds them.
        "reviewer"
      else
        "other"
      end
    end

    reference
  end

  def discussions_props
    discussions_context = {
      type: "discussions",
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
    return discussions_context unless rails_path[:controller] == "discussions" && rails_path[:action] == "show" && rails_path[:number].present?

    discussion = Discussion.find_by(repository: current_repository, number: rails_path[:number])
    return discussions_context unless discussion

    {
      type: "discussion",
      id: discussion.id,
      number: discussion.number,
      repository: {
        id: current_repository.id,
        name: current_repository.name,
        owner: owner.display_login,
      }
    }
  end

  def workspace_editor_props
    return {} unless valid_workspace_editor_request?
    pr_props = pull_request_path_props
    return {} unless pr_props

    @path = rails_path[:path]
    @branch = pr_props[:headRevision]
    file_url = "/#{pr_props[:repository][:nwo]}/blob/#{@branch}/#{@path}"
    [
      pr_props,
      blob_props(file_url),
    ]
  end

  def valid_workspace_editor_request?
    rails_path[:controller] == "workspace_editor/index" && rails_path[:action] == "show" && rails_path[:id].present?
  end
end
