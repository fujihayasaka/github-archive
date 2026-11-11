# typed: true
# frozen_string_literal: true

class Api::IssueArtifacts < Api::App
  include Api::Issues::EnsureIssuesEnabled

  ISSUE_RESOURCE_TYPE = "issue"

  # Create an Artifact for an Issue
  post "/repositories/:repository_id/issues/:issue_number/artifacts", operation_id: :unreleased, read_from_replicas: true do
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:scribe_artifacts_api, current_user, default: false)

    repo = find_repo!
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    ensure_issues_enabled!(repo)

    control_access :custom_role_update_issue,
      repo:,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless repo.writable_by?(current_user)

    data = receive(Hash, required: true)
    type = data["type"] || "generic"
    name = data["name"]
    body = data["body"]

    deliver_error!(422, message: "name is required") if name.blank?
    deliver_error!(503, message: "Artifact storage is not available") unless GitHub.scribe_enabled?(user: current_user)

    begin
      response = GitHub.scribe_client.create_artifact(
        user: current_user,
        resource_type: ISSUE_RESOURCE_TYPE,
        resource_id: issue.id,
        type:,
        name:,
        body:,
      )
    rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
      GitHub.dogstats.increment("api.issue_artifacts.create.error", tags: ["error_class:#{e.class.name}"])
      deliver_error!(503, message: "Artifact storage is temporarily unavailable")
    end

    artifact = response.artifact
    deliver_error!(500, message: "Failed to create artifact") unless artifact

    creator = User.find_by(id: artifact.actor_id)
    deliver_raw(serialize_artifact(artifact, body_context: artifact_body_context(issue), creator:), status: 201)
  end

  # List Artifacts for an Issue
  get "/repositories/:repository_id/issues/:issue_number/artifacts", operation_id: :unreleased, read_from_replicas: true do
    deliver_error!(404) unless current_user
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:scribe_artifacts_api, current_user, default: false)

    repo = find_repo!
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    ensure_issues_enabled!(repo)

    control_access :list_issue_comments,
      repo:,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(503, message: "Artifact storage is not available") unless GitHub.scribe_enabled?(user: current_user)

    type = params[:type]

    begin
      response = GitHub.scribe_client.list_artifacts(
        user: current_user,
        resource_type: ISSUE_RESOURCE_TYPE,
        resource_id: issue.id,
        type:,
      )
    rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
      GitHub.dogstats.increment("api.issue_artifacts.list.error", tags: ["error_class:#{e.class.name}"])
      deliver_error!(503, message: "Artifact storage is temporarily unavailable")
    end

    creators_by_id = User.where(id: response.artifacts.map(&:actor_id).uniq).index_by(&:id)
    body_context = artifact_body_context(issue)
    artifacts = response.artifacts.map { |a| serialize_artifact(a, body_context:, creator: creators_by_id[a.actor_id]) }

    deliver_raw(artifacts)
  end

  # Update an Artifact for an Issue
  patch "/repositories/:repository_id/issues/:issue_number/artifacts/:artifact_number", operation_id: :unreleased, read_from_replicas: true do
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:scribe_artifacts_api, current_user, default: false)

    repo = find_repo!
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    ensure_issues_enabled!(repo)

    control_access :custom_role_update_issue,
      repo:,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless repo.writable_by?(current_user)

    data = receive(Hash, required: true)
    name = data["name"] if data.key?("name")
    body = data["body"] if data.key?("body")

    deliver_error!(422, message: "name or body is required") if name.nil? && body.nil?
    deliver_error!(503, message: "Artifact storage is not available") unless GitHub.scribe_enabled?(user: current_user)

    begin
      response = GitHub.scribe_client.update_artifact(
        user: current_user,
        resource_type: ISSUE_RESOURCE_TYPE,
        resource_id: issue.id,
        number: int_id_param!(key: :artifact_number),
        name:,
        body:,
      )
    rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
      GitHub.dogstats.increment("api.issue_artifacts.update.error", tags: ["error_class:#{e.class.name}"])
      deliver_error!(503, message: "Artifact storage is temporarily unavailable")
    end

    artifact = response.artifact
    deliver_error!(404) unless artifact

    creator = User.find_by(id: artifact.actor_id)
    deliver_raw(serialize_artifact(artifact, body_context: artifact_body_context(issue), creator:))
  end

  # Delete an Artifact for an Issue
  delete "/repositories/:repository_id/issues/:issue_number/artifacts/:artifact_number", operation_id: :unreleased, read_from_replicas: true do
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:scribe_artifacts_api, current_user, default: false)

    repo = find_repo!
    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    ensure_issues_enabled!(repo)

    control_access :custom_role_update_issue,
      repo:,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless repo.writable_by?(current_user)

    deliver_raw({
      number: int_id_param!(key: :artifact_number),
      deleted: true,
    })
  end

  private

  def serialize_artifact(artifact, body_context:, creator: current_user)
    {
      id: artifact.id,
      number: artifact.number,
      type: artifact.type,
      name: artifact.name,
      body: artifact.body,
      body_html: body_html_for_artifact(artifact, body_context:, creator:),
      creator: creator ? { login: creator.display_login, id: creator.id } : nil,
      created_at: artifact.created_at&.to_time&.utc&.iso8601,
      updated_at: artifact.updated_at&.to_time&.utc&.iso8601,
    }
  end

  def body_html_for_artifact(artifact, body_context:, creator:)
    body = artifact.body
    return nil if body.nil?

    GitHub::Goomba::MarkdownPipeline.to_html(body, body_context.merge(current_user: creator, viewer: current_user))
  end

  def artifact_body_context(issue)
    issue.async_body_context.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
