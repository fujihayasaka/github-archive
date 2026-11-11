# typed: strict
# frozen_string_literal: true

module Copilot::Chat::ReferenceBuildersDependency
  # This module is used to build reference objects for various entities.
  # JSON types should match github-ui/packages/copilot-chat/utils/copilot-chat-types.ts, which should match
  # types defined in the Go app at copilot-api/pkg/chat/reference.
  extend T::Helpers

  Reference = T.type_alias { T::Hash[Symbol, T.untyped] }

  sig { params(repository: Repository).returns(Reference) }
  def repository_reference(repository)
    repository_reference_field(repository).merge({
      type: "repository",
    })
  end

  sig { params(issue: Issue).returns(Reference) }
  def issue_reference(issue)
    {
      type: "issue",
      id: issue.id,
      number: issue.number,
      repository: repository_reference_field(T.must(issue.repository)),
      title: issue.title,
      body: issue.body,
      state: issue.state_reason_not_planned? ? "not_planned" : issue.state,
      url: issue.url,
      assignees: issue.assignees.map { |assignee| assignee.display_login },
    }
  end

  sig { params(discussion: Discussion).returns(Reference) }
  def discussion_reference(discussion)
    {
      type: "discussion",
      id: discussion.id,
      number: discussion.number,
      title: discussion.title,
      body: discussion.body,
      user: user_reference_field(T.must(discussion.user)),
      state: discussion.state,
      url: discussion.url,
      authorLogin: discussion.user&.display_login,
      repository: repository_reference_field(T.must(discussion.repository))
    }
  end

  sig { params(pull: PullRequest, include_metadata: T::Boolean).returns(Reference) }
  def pull_request_reference(pull, include_metadata: false)
    reference = {
      type: "pull-request",
      id: pull.id,
      title: pull.title,
      number: pull.number,
      state: pull.state,
      draft: pull.draft,
      url: pull.url,
      authorLogin: pull.user&.display_login,
      repository: repository_reference_field(T.must(pull.repository))
    }

    # Ring 0 PR metadata, preloaded so Copilot Chat can answer common questions
    # without an extra GET /pulls/{number} tool call. Opt-in (gated by a feature
    # flag at the call site) so callers that don't need it — e.g. chat link
    # items — aren't bloated. Keep these keys in sync with
    # context_controller.rb#pull_request_path_props and the Go/TS reference types.
    if include_metadata
      issue = T.must(pull.issue)
      reference = reference.merge(
        body: issue.body&.truncate(4000),
        labels: issue.labels.map(&:name),
        assignees: issue.assignees.map(&:display_login),
        milestone: issue.milestone&.title,
        additions: pull.additions,
        deletions: pull.deletions,
        changedFiles: pull.changed_files,
      )
    end

    reference
  end

  # Builds a file or folder reference, depending on the type of the entry.
  # @param ref_or_oid Can be either a branch name or a commit SHA.
  sig { params(entry: TreeEntry, ref_or_oid: String).returns(Reference) }
  def tree_entry_reference(entry, ref_or_oid)
    common = {
      url: "#{GitHub.url}/#{entry.repository.owner.display_login}/#{entry.repository.name}/#{entry.type}/#{ref_or_oid}/#{entry.path}",
      path: entry.path,
      repoID: entry.repository.id,
      repoOwner: entry.repository.owner.display_login,
      repoName: entry.repository.name,
      ref: ref_or_oid
    }

    common.merge(
      entry.directory? ? {
        type: "folder"
      } : {
        type: "file",
        commitOID: entry.repository.ref_to_sha(ref_or_oid),
        languageName: entry.language&.name
      }
    )
  end

  sig { params(file: ::Figma::File).returns(Reference) }
  def figma_reference(file)
    {
      type: "figma",
      title: file.name,
      id: file.key,
      url: file.url,
      thumbnailUrl: file.thumbnail_url,
      fullImageUrl: file.full_image_url,
    }
  end

  sig { params(repository: Repository, job_id: Integer, workflow_id: Integer).returns(Reference) }
  def job_reference(repository, job_id:, workflow_id:)
    reference = {
      type: "job",
      id: job_id,
      repoId: repository.id,
      repoName: repository.name,
      repoOwner: repository.owner&.display_login,
    }

    # Only include workflow if we have a valid workflow_id
    if workflow_id.present? && workflow_id > 0
      reference[:workflow] = { id: workflow_id }
    end

    reference
  end

  sig { params(url: String).returns(Reference) }
  def github_url_reference(url)
    {
      type: "github-url",
      url: url,
    }
  end

  private

  sig { params(repository: Repository).returns(Reference) }
  def repository_reference_field(repository)
    {
      id: repository.id,
      name: repository.name,
      owner: repository.owner&.display_login,
      ownerLogin: repository.owner&.display_login,
      defaultBranch: repository.default_branch
    }
  end

  sig { params(user: User).returns(Reference) }
  def user_reference_field(user)
    {
      login: user.display_login,
    }
  end
end
