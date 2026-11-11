# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFindingsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :code_review_access_required
  before_action :require_copilot_swe_agent_enabled

  before_action :parse_json_params, only: [:fix, :ignore, :unignore]
  allow_verified_fetch only: [:fix, :ignore, :unignore]

  ENTITY_TYPES = T.let(%w[automated_review_comment annotation].freeze, T::Array[String])
  KV_KEY_PREFIX = "pull_requests/code_review_findings/ignored"
  MAX_IGNORED_ENTITIES = 500

  sig { void }
  def fix # rubocop:disable GitHub/UseRestfulActions
    pull_request = current_repository.issues.find_by_number(params[:pull].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return head(:not_found) if pull_request.nil?

    entity_type = params[:entity_type]
    entity_id = params[:entity_id]
    return head(:bad_request) unless entity_type.in?(ENTITY_TYPES) && entity_id.present?

    entity = find_entity(pull_request, entity_type, entity_id.to_i)
    return head(:not_found) if entity.nil?

    task = create_coding_agent_task(pull_request, entity)
    task_url = repo_task_path(current_repository.owner, current_repository, task.id)
    render json: { task_id: task.id, task_url: task_url }, status: :created
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def ignore # rubocop:disable GitHub/UseRestfulActions
    pull_number = params[:pull].to_i
    entity_type = params[:entity_type]
    entity_id = params[:entity_id]
    return head(:bad_request) unless entity_type.in?(ENTITY_TYPES) && entity_id.present?

    composite_id = "#{entity_type}#{entity_id}"
    ignored_ids = read_ignored_ids(pull_number)
    ignored_ids.add(composite_id)
    write_ignored_ids(pull_number, ignored_ids)

    render json: { ignored_entity_ids: ignored_ids.to_a }, status: :ok
  end

  sig { void }
  def unignore # rubocop:disable GitHub/UseRestfulActions
    pull_number = params[:pull].to_i
    entity_type = params[:entity_type]
    entity_id = params[:entity_id]
    return head(:bad_request) unless entity_type.in?(ENTITY_TYPES) && entity_id.present?

    composite_id = "#{entity_type}#{entity_id}"
    ignored_ids = read_ignored_ids(pull_number)
    ignored_ids.delete(composite_id)
    write_ignored_ids(pull_number, ignored_ids)

    render json: { ignored_entity_ids: ignored_ids.to_a }, status: :ok
  end

  private

  sig { params(pull_request: PullRequest, entity: T.any(AutomatedReviewComment, CheckAnnotation)).returns(CopilotSessions::TaskApi::Task) }
  def create_coding_agent_task(pull_request, entity)
    user = current_user
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: user,
      entry_point: :code_review_findings_fix,
      user_session: user_session,
    )

    CopilotSessions::TaskApi::Task.create(
      repository: current_repository,
      user: user,
      token: token,
      base_ref: pull_request.head_ref,
      create_pull_request: false,
      entry_point: :code_review_findings_fix,
      event_type: "code_review_finding_fix",
      problem_statement: build_problem_statement(entity),
    )
  end

  sig { params(entity: T.any(AutomatedReviewComment, CheckAnnotation)).returns(String) }
  def build_problem_statement(entity)
    case entity
    when AutomatedReviewComment
      build_automated_review_comment_problem_statement(entity)
    when CheckAnnotation
      build_annotation_problem_statement(entity)
    else
      T.absurd(entity)
    end
  end

  sig { params(comment: AutomatedReviewComment).returns(String) }
  def build_automated_review_comment_problem_statement(comment)
    parts = T.let(["Fix the following code review finding:"], T::Array[String])
    parts << "**#{comment.title}**" if comment.title.present?
    parts << comment.message.to_s if comment.message.present?

    review_comment = comment.pull_request_review_comment
    if review_comment
      file_path = T.cast(T.unsafe(review_comment).path, T.nilable(String))
      parts << "File: `#{file_path}`" if file_path.present?
    end

    parts.join("\n\n")
  end

  sig { params(annotation: CheckAnnotation).returns(String) }
  def build_annotation_problem_statement(annotation)
    parts = T.let(["Fix the following check annotation:"], T::Array[String])
    parts << "**#{annotation.title}**" if annotation.title.present?
    parts << annotation.message.to_s if annotation.message.present?

    if annotation.path.present?
      location = +"File: `#{annotation.path}`"
      if annotation.start_line.present?
        location << if annotation.end_line.present? && annotation.end_line != annotation.start_line
          ", Lines: #{annotation.start_line}-#{annotation.end_line}"
        else
          ", Line: #{annotation.start_line}"
        end
      end
      parts << location
    end

    parts.join("\n\n")
  end

  sig { params(pull_request: PullRequest, entity_type: String, entity_id: Integer).returns(T.nilable(T.any(AutomatedReviewComment, CheckAnnotation))) }
  def find_entity(pull_request, entity_type, entity_id)
    case entity_type
    when "automated_review_comment"
      pull_request.automated_review_comments.find_by(id: entity_id)
    when "annotation"
      repository = T.must(pull_request.repository)
      CheckAnnotation.where(repository_id: repository.id)
        .joins(:check_suite)
        .where(check_suites: { head_sha: pull_request.head_sha })
        .find_by(id: entity_id)
    end
  end

  sig { void }
  def code_review_access_required
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository, bypass_quota_check: true)
    render_404 unless access.can_create_review_request?
  end

  sig { void }
  def require_copilot_swe_agent_enabled
    return true if Rails.env.development?
    render_404 unless current_repository.copilot_swe_agent_enabled?(current_user)
  end

  sig { params(pull_number: Integer).returns(T::Set[String]) }
  def read_ignored_ids(pull_number)
    kv = PullRequests::KV.for_repository(current_repository)
    key = kv_key(pull_number)
    json = kv.get(key).value { nil }
    return Set.new if json.nil?

    parsed = JSON.parse(json)
    Set.new(Array(parsed))
  rescue JSON::ParserError
    Set.new
  end

  sig { params(pull_number: Integer, ids: T::Set[String]).void }
  def write_ignored_ids(pull_number, ids)
    kv = PullRequests::KV.for_repository(current_repository)
    key = kv_key(pull_number)

    if ids.empty?
      kv.del(key)
    else
      truncated = ids.to_a.last(MAX_IGNORED_ENTITIES)
      kv.set(key, JSON.generate(truncated))
    end
  end

  sig { params(pull_number: Integer).returns(String) }
  def kv_key(pull_number)
    "#{KV_KEY_PREFIX}/pr#{pull_number}"
  end
end
