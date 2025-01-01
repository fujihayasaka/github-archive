# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewController < AbstractRepositoryController
  extend T::Sig

  include CopilotChatHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :feature_required
  before_action :find_pull_request, only: [:new]

  allow_verified_fetch only: [:new]

  EXPERIMENT_HEADER_NAME = /HTTP_X_EXPERIMENT_(.*)/

  sig { void }
  def new
    respond_to do |format|
      format.json do
        result, status = create_code_review
        render json: result, status: status
      end
    end
  end

  sig { void }
  def has_access # rubocop:disable GitHub/UseRestfulActions
    copilot_enabled = with_database_error_fallback(fallback: false) { copilot_chat_enabled_for_current_user? }
    render status: :ok, json: { copilot_enabled: copilot_enabled }
  end

  private

  sig do
    returns([
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess],
        T::Hash[Symbol, T.untyped]
      ),
      Symbol
    ])
  end
  def create_code_review
    serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
    include_full_files = user_feature_enabled?(:copilot_reviews_include_full_files)
    reference = T.must(serializer.to_hash(@pull_request, include_diff: true, include_full_files: include_full_files))

    render_404 unless reference.present?

    experiment_headers = request.headers.filter_map do |k, v|
      exp_name = k.match(EXPERIMENT_HEADER_NAME)&.captures&.first
      if exp_name
        ["X-Experiment-#{exp_name}", v]
      end
    end.to_h

    args = {
      references: [reference] + coding_guideline_references,
      role: "user",
      experiment_headers: experiment_headers,
    }
    result, status = capi.create_code_review(**args)
    [result, :ok]
  rescue CopilotAPI::NotFoundError, CopilotAPI::UnauthorizedError => err
    [{ error: err }, :not_found]
  rescue CopilotAPI::NetworkError => err
    Failbot.report(err)
    [{ error: err }, :internal_server_error]
  end

  sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
  def coding_guideline_references
    return [] unless coding_guidelines_available?
    Copilot::CodingGuideline.references_for(current_repository.id)
  end

  sig { returns(T.nilable(T::Boolean)) }
  def coding_guidelines_available?
    current_user&.feature_enabled?(:copilot_coding_guidelines) &&
      current_repository.owner.organization? &&
      ::Copilot::Organization.new(current_repository.owner).can_use_copilot_enterprise_features?
  end

  sig { returns(Copilot::DecryptedToken) }
  def mint_token
    new_access = Apps::Internal.integration(:copilot_pull_request_reviewer)&.grant(current_user, { user_session: user_session })
    # extended_expiry actually means that our own (shorter) oauth_access_expiry value is used
    token, _ = new_access.redeem(extended_expiry: true)
    Copilot::DecryptedToken.from(token)
  end

  sig { void }
  def feature_required
    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    render_404 unless code_review_access.can_request_via_button?
  end

  sig { void }
  def find_pull_request
    @pull_request = T.let(current_repository.issues.find_by_number(params[:pull].to_i)&.pull_request, T.nilable(PullRequest))
    render_404 unless @pull_request.present?
  end

  sig { returns Copilot::User::CopilotApi }
  def capi
    Copilot::User::CopilotApi.new(
      T.must(current_user),
      integration_id: CopilotAPI::COPILOT_4_PRS_INTEGRATION_ID,
      session: user_session,
      real_ip: remote_ip,
      token: mint_token
    )
  end
end
