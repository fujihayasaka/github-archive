# typed: true
# frozen_string_literal: true

module BypassRequestsControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include Repos::RulesHelper

  requires_ancestor { ApplicationController }

  FETCH_ENDPOINTS = T.let([
    :create,
    :update,
    :bypass_request_requesters,
    :bypass_request_approvers,
    :approvers,
  ], T::Array[Symbol])

  included do
    T.bind(self, T.class_of(ApplicationController))

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Spokes,
      ApplicationRecord::Authnd,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Memex,
      ApplicationRecord::RepositoriesPushes,
      only: [:index, :new, :show, :bypass_request_requesters, :bypass_request_approvers]

    depends_on_clusters ApplicationRecord::Copilot,
      optional: true,
      only: [:index, :new, :show]

    sig { returns(String) }
    def self.react_bundle_name
      "delegated-bypass"
    end

    # Before actions
    before_action :find_rule_suite, only: [:new, :create]
    before_action :plan_supports_enterprise_rulesets
  end

  REQUEST_TYPES = {
    Exemptions::Evaluators::PushRulesetBypass.request_type => "Push Bypass Request",
    Exemptions::Evaluators::RepositoryPolicyRulesetBypass.request_type => "Repository Policy Bypass Request",
   }

  abstract!

  sig { abstract.returns(RuleEngine::Types::RuleSource) }
  protected def current_source; end
  sig { abstract.returns(Symbol) }
  protected def selected_link; end

  sig { abstract.returns(String) }
  protected def layout; end

  sig { abstract.returns(String) }
  protected def title; end

  sig { overridable.returns(T.nilable(String)) }
  def base_exemption_url
    nil
  end

  sig { void }
  def index
    payload = rules_bypass_requests_payload(
      viewing_source: current_source,
      filter: {
        approver: params[:approver],
        requester: params[:requester],
        time_period: params[:time_period],
        request_status: params[:request_status],
        repository: params[:repository],
        organization: params[:organization],
      },
      page: params[:page].to_i,
      base_exemption_url:,
      request_types: REQUEST_TYPES.keys,
      repo_exemptions_base_url_suffix: nil
    )

    # For now, we base this on the type(s) of bypass requests which were found. At some point we might start letting the
    # user filter for a specific subset of request types (request_types above, currently not settable). In that case,
    # change the UI to match what the user filtered for and get rid of this .map{....} code.
    request_types = payload["exemptionRequests"].map { _1["requestType"] }
    request_type = request_types.count == 1 ? request_types.first : "multiple_bypass_types"

    render_react_app(
      payload:,
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_source, request_type, is_stafftools: stafftools?) },
      title:,
      page_data: {
        selected_link:,
        sidebar: :policies
      },
      layout:,
    )
  end

  sig { void }
  def new
    return render_404 unless current_source.is_a?(Repository)

    # Only allow actor to make request on behalf of self
    return render_404 if @rule_suite.actor_type == "User" && @rule_suite.actor_id != current_user&.id
    # if pending request, redirect to it

    existing_request = RuleEngine::BypassDelegation.existing_ruleset_request(@rule_suite, T.must(current_user), @request_type)
    return redirect_to action: :show, number: existing_request.number if existing_request

    payload = T.must(new_exemption_request_payload(@rule_suite))
    payload[:helpUrl] = DocsUrlConfig.url_for("code-security/about-delegated-bypass-for-push-protection")

    render_react_app(
      payload:,
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_source, @request_type) },
      title: REQUEST_TYPES[@request_type],
    )
  end

  sig { void }
  def create
    return render_404 unless current_source.is_a?(Repository)

    body = request&.body
    message = JSON.parse(body.read)["message"]&.strip
    begin
      if current_source.feature_flag_enabled?(:delegated_bypass_fork_fix, default: false)
        request = if @request_type == Exemptions::Evaluators::PushRulesetBypass.request_type
          Exemptions::Evaluators::PushRulesetBypass.create_request!(@rule_suite, T.must(current_user), message)
        elsif @request_type == Exemptions::Evaluators::RepositoryPolicyRulesetBypass.request_type
          Exemptions::Evaluators::RepositoryPolicyRulesetBypass.create_request!(@rule_suite, T.must(current_user), message)
        else
          return render_404
        end
      else
        request = RuleEngine::BypassDelegation.create_ruleset_request!(@rule_suite, T.must(current_user), @request_type, message)
      end
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end
    render json: { success: true, request_number: request.number, expires_at: request.expires_at }, status: 201
  end

  sig { void }
  def update
    return render_404 unless current_source.is_a?(Repository)

    number = params.require(:number)
    return render_404 unless (user = current_user)
    exemption_request = Exemptions::ExemptionRequest.where(repository: current_source, number:, resource_owner_type: "RuleEngine::RuleSuite").first
    return render_404 unless exemption_request
    return render json: { error: "Request is expired" }, status: :forbidden if exemption_request.expired?
    return render json: { error: "Request is completed" }, status: :forbidden if exemption_request.completed?
    return render json: { error: "Request is cancelled" }, status: :forbidden if exemption_request.cancelled?

    body = request&.body
    response = JSON.parse(body.read)
    status = response["status"]&.strip&.downcase

    if status == "dismiss"
      response_id = response["responseId"]
      exemption_response = Exemptions::ExemptionResponse.where(id: response_id, reviewer_id: T.must(current_user).id).first
      return render_404 unless exemption_response
      exemption_response.status = :dismissed
      exemption_response.save!
      return render json: { success: true }, status: 201
    end

    if status == "cancel"
      if exemption_request.status == "pending" || exemption_request.status == "rejected"
        exemption_request.status = :cancelled
        exemption_request.save!
        return render json: { success: true }, status: 201
      else
        return render json: { error: "Request cannot be cancelled because it is #{exemption_request.status}" }, status: :forbidden
      end
    end

    # Only delegated admins can approve/reject the exemption request (approve/reject)
    # Admins can't approve own request
    return render json: { error: "Actor is not a valid reviewer" }, status: :forbidden unless exemption_request.is_valid_reviewer?(user)

    if status == "approve"
      Exemptions::ExemptionResponse.approve!(exemption_request, user)
    elsif status == "reject"
      Exemptions::ExemptionResponse.reject!(exemption_request, user)
    end

    render(
      json: { success: true },
      status: 201,
    )
  end

  sig { void }
  def show
    return render_404 unless current_source.is_a?(Repository)

    number = params.require(:number)
    exemption_request = Exemptions::ExemptionRequest.where(repository: current_source, number:, resource_owner_type: "RuleEngine::RuleSuite").first
    # Redirect to new page unless we find an exemption request
    unless exemption_request
      return render_404
    end

    render_react_app(
      payload: exemption_request_payload(exemption_request, current_user, responses: exemption_request.responses),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_source, exemption_request.request_type, is_stafftools: stafftools?) },
      title: REQUEST_TYPES[exemption_request.request_type],
    )
  end

  def bypass_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_source))
  end

  def bypass_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_source))
  end

  sig { void }
  def approvers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_source.is_a?(Repository)

    number = params.require(:number)
    ruleset_id = params.require(:rulesetId)

    exemption_request = Exemptions::ExemptionRequest.find_by(repository: current_source, number:)
    ruleset = RepositoryRuleset.find_by(id: ruleset_id)

    return render_404 if exemption_request.nil? || ruleset.nil?

    approvers = ruleset.bypass_actors
      .select { |bypass_actor| bypass_actor.actor_type != "Integration" }
      .map { |bypass_actor| RulesEngine::ReactPayload.bypass_actor_as_json(bypass_actor) }

    render(
      json: { approvers: },
      status: 200,
    )
  end

  private

  sig { void }
  def find_rule_suite
    id = params.require(:encoded)
    # expect <exemption request type>-<id>-<suite_repo_id (optional)>
    begin
      @request_type, decoded_id, suite_repo_id = Base64.urlsafe_decode64(id).split("-")
      @decoded_id = T.let(decoded_id&.to_i, T.nilable(Integer))
      return render_404 unless @decoded_id
      @rule_suite = if suite_repo_id
        RuleEngine::RuleSuite.find_by(id: @decoded_id, repository_id: suite_repo_id)
      else
        RuleEngine::RuleSuite.find_by(id: @decoded_id)
      end
      render_404 unless @rule_suite
    rescue ArgumentError
      render_404
    end
  end

  sig { void }
  def plan_supports_enterprise_rulesets
    render_404 unless current_source.plan_supports?(:enterprise_rulesets)
  end

  sig { overridable.returns(T::Boolean) }
  protected def stafftools?
    false
  end

end
