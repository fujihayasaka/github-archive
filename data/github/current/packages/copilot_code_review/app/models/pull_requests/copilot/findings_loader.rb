# typed: strict
# frozen_string_literal: true

# Shared service for fetching Copilot code review findings from the Copilot API.
# Used by both FindingsCountCache (for cache-miss count queries) and
# CodeReviewFindingsController (for full findings retrieval).
class PullRequests::Copilot::FindingsLoader
  DEFAULT_COUNTED_FINDINGS_SEVERITIES = T.let(Set["critical", "high"].freeze, T::Set[String])

  sig do
    params(
      user: User,
      user_session: T.nilable(UserSession),
      remote_ip: T.nilable(String),
      entry_point: Symbol,
    ).void
  end
  def initialize(user:, user_session: nil, remote_ip: nil, entry_point: :code_review_findings_fetch)
    @user = user
    @user_session = user_session
    @remote_ip = remote_ip
    @entry_point = entry_point
  end

  # Fetches full findings response from CAPI, normalizing findings to HashWithIndifferentAccess.
  sig { params(pull_request: PullRequest, view: T.nilable(String)).returns(ActiveSupport::HashWithIndifferentAccess) }
  def fetch_findings(pull_request, view: nil)
    repo_id = pull_request.repository_id
    result = if view.present?
      capi.get_findings(repo_id: repo_id, pull_request_id: pull_request.id, head_sha: pull_request.head_sha, view: view)
    else
      capi.get_findings(repo_id: repo_id, pull_request_id: pull_request.id, head_sha: pull_request.head_sha)
    end
    response = T.cast(result, ActiveSupport::HashWithIndifferentAccess)
    if response[:findings].is_a?(Array)
      response[:findings] = response[:findings].map { |f| f.is_a?(ActiveSupport::HashWithIndifferentAccess) ? f : f.with_indifferent_access }
    end
    response
  end

  # Fetches only the findings count from CAPI.
  sig { params(pull_request: PullRequest).returns(Integer) }
  def fetch_findings_count(pull_request)
    response = fetch_findings(pull_request)
    findings = response[:findings]
    return 0 unless findings.is_a?(Array)

    findings.count { |finding| DEFAULT_COUNTED_FINDINGS_SEVERITIES.include?(finding[:severity]) }
  end

  private

  sig { returns(Copilot::User::CopilotApi) }
  def capi # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
    @capi ||= T.let(begin
      token = CopilotSessions::CopilotApiToken.get_encrypted(
        user: @user,
        entry_point: @entry_point,
        user_session: @user_session,
      )

      Copilot::User::CopilotApi.new(
        @user,
        integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        session: @user_session,
        real_ip: @remote_ip,
        token: token,
      )
    end, T.nilable(Copilot::User::CopilotApi))
  end
end
