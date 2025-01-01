# typed: true
# frozen_string_literal: true

class SecretScanningBypassRequestsController < AbstractRepositoryController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency
  include ReactHelper
  include Repos::RulesHelper
  include SecretScanning::BypassDelegation
  include SecretScanning::Constants

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:index, :new, :show, :bypass_request_requesters, :bypass_request_approvers]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:new, :show, :index, :bypass_request_requesters, :bypass_request_approvers]

  allow_verified_fetch only: [:create, :update, :approvers]

  # Before actions
  before_action :login_required
  before_action :check_delegated_bypass_enabled
  before_action :decode_params, only: [:new, :create]
  before_action :check_repository_write_access, only: [:new, :create]
  before_action :require_rule_suite_belongs_to_user, only: [:new, :create]
  before_action :manage_security_products_permission_required, only: [:bypass_request_requesters, :bypass_request_approvers]
  before_action :check_list_access, only: [:index]
  before_action :require_user_can_read_repo, only: [:show]

  ERROR_TYPE = "SecretScanningBypassRequestError"

  sig { returns(String) }
  def self.react_bundle_name
    "delegated-bypass"
  end

  sig { void }
  def index
    return render_404 if current_repository.fork?
    render_react_app(
      payload: rules_bypass_requests_payload(
        viewing_source: current_repository,
        filter: {
          approver: params[:approver],
          requester: params[:requester],
          time_period: params[:time_period],
          request_status: params[:request_status],
          repository: nil,
        },
        page: params[:page].to_i,
        base_exemption_url: "../../../secret_scanning/exemptions/",
        request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_repository, EXEMPTION_REQUEST_TYPE) },
      title: "Settings · Secret Scanning Bypass Requests · #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :secret_scanning_bypass_requests
      },
      layout: "layouts/bypass_requests/sidebar_container",
      ssr: false,
    )
  end

  sig { void }
  def new
    # if pending request, redirect to it
    existing_request = existing_secret_scanning_request(@rule_suite, T.must(current_user), T.must(@resource_id))
    return redirect_to action: :show, number: existing_request.number if existing_request
    payload = T.must(new_exemption_request_payload(@rule_suite, resource_id: T.must(@resource_id)))

    # Fetching only the teams and users, but not roles, so we can show all valid approvers for the request in the UI
    users, teams, error = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewer_users_teams(current_repository, T.must(current_user))
    if error
      log_service_error(
        log_msg: "Service failed to get reviewers using repository ID",
        method_name: __method__.to_s,
        error_message: error)
      return render json: { error: error }, status: :internal_server_error
    end
    payload[:approvers] = [
      users&.map { |user| { id: user.id, display_login: user.display_login } },
      teams&.map { |team| { id: team.id, name: team.name, slug: team.slug, org_name: team.organization&.display_login } },
    ]

    if current_repository.owner.organization? && SecretScanning::Features::Org::PushProtection.new(current_repository.owner).custom_message_active?
      payload[:orgGuidanceUrl] = current_repository.owner.get_push_protection_custom_message
    end
    payload[:helpUrl] = DocsUrlConfig.url_for("code-security/working-with-push-protection-from-the-command-line-removing-a-secret-introduced-by-an-earlier-commit-on-your-branch")

    render_react_app(
      app_name: "delegated-bypass",
      payload:,
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_repository, EXEMPTION_REQUEST_TYPE) },
      title: "Secret Scanning Bypass Request",
      ssr: true,
    )
  end

  sig { void }
  def create
    body = request&.body
    begin
      json_body = JSON.parse(body.read)
    rescue JSON::ParserError
      log_service_error(
        log_msg: "JSON body not present or is invalid JSON",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return render json: { error: "Invalid form content" }, status: :unprocessable_entity
    end
    message = json_body["message"]&.strip
    if !message
      log_service_error(
        log_msg: "'message' param not provided",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return render json: { error: "Comment is mandatory" }, status: :unprocessable_entity
    end
    if message.length > 2048
      log_service_error(
        log_msg: "'message' param too long",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return render json: { error: "Comment is too long" }, status: :unprocessable_entity
    end
    reason = json_body["reason"]&.strip
    if !reason
      log_service_error(
        log_msg: "'reason' param not provided",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return render json: { error: "Reason is mandatory" }, status: :unprocessable_entity
    end
    begin
      GitHub.logger.info(
        "SecretScanningBypassRequestsController#create",
        "rule_suite_id": @rule_suite.id,
        "rule_suite_actor_login": @rule_suite.actor.display_login,
        "current_user_id": current_user&.id,
        "current_user_login": current_user&.display_login,
        "resource_id": @resource_id,
      )
      request = create_secret_scanning_request!(@rule_suite.id, T.must(current_user), T.must(@resource_id), reason, message)
      GitHub.instrument("secret_scanning_push_protection_request.request", {
        actor: current_user,
        repository: current_repository,
        org: current_repository.organization,
        number: request.number,
      })
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    render json: { success: true, number: request.number, redirect_uri: secret_scanning_bypass_request_url(number: request.number) }, status: 201
  end

  sig { void }
  def update
    number = params.require(:number)
    return render_404 unless (user = current_user)
    exemption_request = Exemptions::ExemptionRequest.where(request_type: EXEMPTION_REQUEST_TYPE, repository: current_repository, number:).first
    return render_404 unless exemption_request
    return render json: { error: "Request has expired" }, status: :forbidden if exemption_request.expired?

    body = request&.body
    response_body = JSON.parse(body.read)
    status = response_body["status"]&.strip&.downcase
    is_valid_reviewer = exemption_request.is_valid_reviewer?(user)

    if status == "cancel"
      # Only bypass reviewers and the requesting user can cancel the request
      return render json: { error: "Only the requester and bypass reviewers can cancel requests" }, status: :forbidden unless is_valid_reviewer || exemption_request.requester == current_user

      # A request can only be cancelled if it hasn't yet been completed.
      if exemption_request.status.to_sym != :completed
        exemption_request.status = :cancelled
        exemption_request.save!
      end
      # Regardless, redirect back to show. This will refresh the page's state and show the cancellation (and/or any other new events).
      return render json: { success: true }, status: 201
    end

    if status == "dismiss"
      return render json: { error: "Only bypass reviewers can dismiss a response" }, status: :forbidden unless is_valid_reviewer
      response_id = response_body["responseId"]
      exemption_response = Exemptions::ExemptionResponse.where(id: response_id, reviewer_id: T.must(current_user).id).first
      return render_404 unless exemption_response
      exemption_response.status = :dismissed
      exemption_response.save!
      return render json: { success: true }, status: 201
    end

    # Only delegated admins can approve/reject the exemption request (approve/reject)
    # Admins can't approve own request
    return render json: { error: "Actor is not a valid reviewer" }, status: :forbidden unless is_valid_reviewer

    if status == "approve"
      response_body = Exemptions::ExemptionResponse.approve!(exemption_request, user)
      GitHub.instrument("secret_scanning_push_protection_request.approve", {
        actor: current_user,
        repository: current_repository,
        org: current_repository.organization,
        number: exemption_request.number,
      })
    elsif status == "reject"
      response_body = Exemptions::ExemptionResponse.reject!(exemption_request, user)
      GitHub.instrument("secret_scanning_push_protection_request.deny", {
        actor: current_user,
        repository: current_repository,
        org: current_repository.organization,
        number: exemption_request.number,
      })
    end

    render(
      json: { success: true },
      status: 201,
    )
  end


  sig { void }
  def show
    number = params.require(:number)
    exemption_request = Exemptions::ExemptionRequest.where(request_type: EXEMPTION_REQUEST_TYPE, repository: current_repository, number:).first
    # Redirect to new page unless we find an exemption request
    unless exemption_request
      return render_404
    end
    render_react_app(
      app_name: "delegated-bypass",
      payload: exemption_request_payload(exemption_request.resource_owner, exemption_request, current_user, responses: exemption_request.responses),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_repository, EXEMPTION_REQUEST_TYPE) },
      title: "Secret Scanning Bypass Request",
      ssr: true
    )
  end

  sig { void }
  def bypass_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_repository, RuleEngine::Rules::SecretScanningRule::RULE_NAME))
  end

  sig { void }
  def bypass_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_repository, RuleEngine::Rules::SecretScanningRule::RULE_NAME))
  end

  private

  sig { void }
  def decode_params
    id = params.require(:encoded)
    # expect <exemption request type>-<rulesuite id>-<resource id>
    begin
      type, rule_suite_id, resource_id = Base64.urlsafe_decode64(id).split("-")
      @rule_suite_id = T.let(rule_suite_id&.to_i, T.nilable(Integer))
      return render_404 unless @rule_suite_id
      @rule_suite = RuleEngine::RuleSuite.find_by(id: @rule_suite_id)
      return render_404 unless @rule_suite
      @resource_id = T.let(resource_id&.to_s, T.nilable(String))
      render_404 unless @resource_id
    rescue ArgumentError
      render_404
    end
  end

  sig { void }
  def check_delegated_bypass_enabled
    render_404 unless SecretScanning::Features::Repo::DelegatedBypass.new(current_repository).enabled?
  end

  sig { void }
  def check_repository_write_access
    render_404 unless current_repository.writable_by?(current_user)
  end

  sig { void }
  def require_rule_suite_belongs_to_user
    render_404 if @rule_suite.actor_type == "User" && @rule_suite.actor_id != current_user&.id
  end

  sig { void }
  def require_user_can_read_repo
    render_404 unless current_user_can_read_repo?
  end

  sig { void }
  def check_list_access
    render_404 unless current_repository.can_view_delegated_bypass_requests_list?(current_user)
  end

  sig { params(log_msg: String, method_name: String, error_message: String).void }
  def log_service_error(log_msg:, method_name:, error_message:)
    GitHub.logger.error(
      log_msg,
      "code.namespace": self.class.name,
      "code.function": method_name,
      "controller.name": self.class.name,
      "controller.action": method_name,
      "repo.id": current_repository.id,
      "error.type": SecretScanning::Services::AlertsService::ERROR_TYPE,
      "error.message": error_message
    )
  end
end
