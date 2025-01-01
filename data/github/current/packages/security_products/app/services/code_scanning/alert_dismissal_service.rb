# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AlertDismissalService < SecurityProduct::Service
    extend AlertDependency

    class AlertDismissalError < StandardError
    end

    class PendingRequestExistsError < AlertDismissalError
    end

    class AlertNotFoundError < AlertDismissalError
    end

    EXEMPTION_REQUEST_TYPE = "code_scanning_alert_dismissal"

    # This method requires an actor and options as params but we don't need to check them at the moment so we use T.untyped
    sig { override.params(actor: T.nilable(User), options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor: nil, options: nil)
      return SecurityProduct::Result.new(false) unless repository.owner.is_a?(Organization)
      if !CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository: repository)
        message = if repository.advanced_security_products_bundled?
          :advanced_security_disabled
        else
          :code_security_disabled
        end
        return SecurityProduct::Result.new(false, message)
      end
      SecurityProduct::Result.new(true)
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      delegated_dismissal_enabled?
    end

    sig { returns(T::Boolean) }
    def delegated_dismissal_enabled?
      return false unless repository.owner.is_a?(Organization)

      CodeScanningRepositoryConfig.new(repository).code_scanning_delegated_alert_dismissal_settings_enabled?
    end

    # on_enable and on_disable are called when the user enables or disables delegated alert dismissal, or updates the configuration.
    # The methods are typically called via the SecurityProduct::ToggledServiceCollection class.
    # When changing these methods, please ensure that the behavior is idempotent, as this is a requirement for this interface.
    sig do
      override
      .params(
        actor: User,
        options: T.untyped
      )
      .returns(SecurityProduct::Result)
    end
    def on_enable(actor:, options:)
      CodeScanningRepositoryConfig.new(repository).enable_code_scanning_delegated_alert_dismissal_settings(actor:)
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end

    sig do
      override
      .params(
        actor: User,
        options: T.untyped
      )
      .returns(SecurityProduct::Result)
    end
    def on_disable(actor:, options:)
      CodeScanningRepositoryConfig.new(repository).disable_code_scanning_delegated_alert_dismissal_settings(actor:)
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end

    sig { override.returns(Symbol) }
    def to_sym
      :code_scanning_delegated_alert_dismissal
    end

    sig do
      params(
        repository: Repository,
        requester: RuleEngine::Types::Actor,
        alert_number: Integer,
        resolution: Integer,
        resolution_note: T.nilable(String),
        pr_review_thread_id: T.nilable(Integer),
        campaign_id: T.nilable(Integer),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def self.request_dismissal(repository:, requester:, alert_number:, resolution:, resolution_note:, pr_review_thread_id:, campaign_id:)
      existing_requests = Exemptions::ExemptionRequest.where(
        request_type: EXEMPTION_REQUEST_TYPE,
        repository: repository,
        resource_identifier: resource_identifier(repository:, alert_number:),
      )

      pending_requests = existing_requests.any? { |request| request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending }
      raise PendingRequestExistsError, "A pending request already exists" if pending_requests

      response = GitHub::Turboscan.alert(
        repository_id: repository.id,
        number: alert_number,
      )
      alert = response&.data&.result
      alert_title = alert.present? ? alert_title(alert) : "Code scanning alert"

      request = begin
        Exemptions::ExemptionRequest.create!(
          resource_owner: repository,
          requester: requester,
          repository: repository,
          resource_identifier: resource_identifier(repository:, alert_number:),
          request_type: EXEMPTION_REQUEST_TYPE,
          expires_at: 1.year.from_now,
          metadata: {
            "resolution": resolution.to_s,
            "alert_number": alert_number.to_s,
            "pr_review_thread_id": pr_review_thread_id.to_s,
            "campaign_id": campaign_id.to_s,
            "alert_title": alert_title,
          },
          requester_comment: resolution_note,
        )
      rescue StandardError => e
        Failbot.report(
          e,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert.number": alert_number,
          "gh.code_scanning.alert_dismissal.requester": requester,
        )
        raise AlertDismissalError, "Failed to create the exemption request"
      end

      payload = {
        actor: requester,
        repo: repository,
        dismissal_request_id: request.id,
        alert_number:,
      }
      GitHub.instrument("code_scanning.alert_closure_requested", payload)

      { request:, alert: }
    end

    sig do
      params(
        repository: Repository,
        reviewer: User,
        request_id: Integer,
        message: T.nilable(String)
      ).void
    end
    def self.approve_request(repository:, reviewer:, request_id:, message: nil)
      request = Exemptions::ExemptionRequest.find_by(
        request_type: EXEMPTION_REQUEST_TYPE,
        repository:,
        id: request_id,
      )
      raise AlertDismissalError, "The request doesn't exist" unless request
      raise AlertDismissalError, "The request is not pending" unless request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending

      begin
        Exemptions::ExemptionResponse.approve!(request, reviewer, message:)
      rescue StandardError => e
        Failbot.report(
          e,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert_dismissal.request_id": request_id,
          "gh.code_scanning.alert_dismissal.reviewer": reviewer,
        )
        raise AlertDismissalError, "Failed to approve the exemption request"
      end

      payload = {
        actor: reviewer,
        repo: repository,
        dismissal_request_id: request.id,
        alert_number: request.metadata["alert_number"].to_i,
      }
      GitHub.instrument("code_scanning.alert_closure_approved", payload)
    end

    sig do
      params(
        repository: Repository,
        reviewer: User,
        request_id: Integer,
        message: T.nilable(String)
      ).void
    end
    def self.reject_request(repository:, reviewer:, request_id:, message: nil)
      request = Exemptions::ExemptionRequest.find_by(
        request_type: EXEMPTION_REQUEST_TYPE,
        repository:,
        id: request_id,
      )
      raise CodeScanning::AlertDismissalService::AlertDismissalError, "The request doesn't exist" unless request
      raise CodeScanning::AlertDismissalService::AlertDismissalError, "The request is not pending" unless request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending

      begin
        Exemptions::ExemptionResponse.reject!(request, reviewer, message:)
      rescue StandardError => e
        Failbot.report(
          e,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert_dismissal.request_id": request_id,
          "gh.code_scanning.alert_dismissal.reviewer": reviewer,
        )
        raise AlertDismissalError, "Failed to reject the exemption request"
      end

      payload = {
        actor: reviewer,
        repo: repository,
        dismissal_request_id: request.id,
        alert_number: request.metadata["alert_number"].to_i,
      }
      GitHub.instrument("code_scanning.alert_closure_denied", payload)
    end

    sig do
      params(
        dismissal_request: Exemptions::ExemptionRequest,
        status: T.nilable(String),
        message: String,
        user: User,
        repo: Repository,
      ).void
    end
    def self.review_dismissal_request!(dismissal_request:, status:, message:, user:, repo:)
      if status == "approve"
        approve_request(
          repository: repo,
          reviewer: user,
          request_id: dismissal_request.id,
          message:,
        )
      elsif status == "deny" || status == "reject"
        reject_request(
          repository: repo,
          reviewer: user,
          request_id: dismissal_request.id,
          message:,
        )
      else
        raise AlertDismissalError, "Invalid status: #{status}"
      end
    end

    MSG_LIMIT = 2048
    sig { params(message: T.nilable(String)).returns([T::Boolean, T.nilable(String)]) }
    def self.validate_request_message(message)
      message ||= ""
      message = message.strip
      return false, "Message is required" if message.empty?
      return false, "Message exceeds #{MSG_LIMIT} character limit" if message.length > MSG_LIMIT
      [true, nil]
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
        viewer: User,
      ).returns(T::Array[T.untyped])
    end
    def self.get_timeline_events(repository:, alert_number:, viewer:)
      requests = Exemptions::ExemptionRequest.where(
        request_type: EXEMPTION_REQUEST_TYPE,
        resource_identifier: resource_identifier(repository:, alert_number:),
        repository_id: repository.id,
      )

      events = []
      requests.each do |request|
        show_dismissal_actions = request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending && request.is_valid_reviewer?(viewer)

        events << CodeScanning::AlertTimelineEvent.new(
          type: :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REQUESTED,
          user_id: request.requester_id,
          timestamp: Google::Protobuf::Timestamp.new(seconds: request.created_at.to_i),
          resolution: Turboscan::Proto::ResultResolution.lookup(request.metadata["resolution"].to_i),
          resolution_note: request.requester_comment,
          request_id: request.id,
          show_dismissal_actions:,
        )

        request.responses.each do |response|
          events << CodeScanning::AlertTimelineEvent.new(
            type: :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REVIEWED,
            user_id: response.reviewer_id,
            timestamp: Google::Protobuf::Timestamp.new(seconds: response.created_at.to_i),
            compute_status: response.status,
            reviewer_comment: response.message,
          )
        end
      end

      events
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(String)
    end
    def self.resource_identifier(repository:, alert_number:)
      "#{repository.id}/#{alert_number}"
    end

    sig { params(org: Organization).returns(T::Array[Integer]) }
    def self.get_org_reviewer_ids(org)
      visible_role_ids = Authz.domain.roles.visible_org_role_ids_with_fgp(
        org, :review_org_code_scanning_dismissal_requests
      )

      actor_types_and_ids = Authz.domain.user_roles.batch_role_assignments_with_role_ids_for_target(
        target: org, role_ids: visible_role_ids,
      )

      user_ids = actor_types_and_ids.fetch(User.user_role_target_type, [])

      team_ids = actor_types_and_ids.fetch(Team.user_role_target_type, [])
      user_ids.concat(Team.member_ids_of(team_ids, immediate_only: false))

      business_team_ids = []

      if org.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
        business_team_ids = actor_types_and_ids.fetch(BusinessTeam.user_role_target_type, [])
        user_ids.concat(Orgs.domain.teams.user_ids_for_business_teams(business_team_ids))
      end

      (user_ids + org.admin_ids).uniq
    end

    sig do
      params(
        request: Exemptions::ExemptionRequest,
        user: User,
      ).returns(T::Boolean)
    end
    def self.can_review_dismissal_request?(request:, user:)
      repo = T.must(request.repository)
      return false unless repo.owner&.organization? # CodeScanningAlertDismissal are only valid for org owned repos
      org = T.cast(T.must(repo.owner), Organization)

      return false unless can_review_org_requests?(org:, user:)

      return Authz.domain.check_allowed(user, :org_bypass_code_scanning_dismissal_requests, org) if request.requester == user

      true
    end

    sig do
      params(
        org: Organization,
        user: User
      ).returns(T::Boolean)
    end
    def self.can_view_org_requests?(org:, user:)
      Authz.domain.check_allowed(user, :view_org_code_scanning_dismissal_requests, org)
    end

    sig do
      params(
        org: Organization,
        user: User
      ).returns(T::Boolean)
    end
    def self.can_review_org_requests?(org:, user:)
      Authz.domain.check_allowed(user, :review_org_code_scanning_dismissal_requests, org)
    end

    sig do
      params(
        business: Business,
        user: User
      ).returns(T::Boolean)
    end
    def self.is_valid_business_reviewer?(business:, user:)
      return false unless business.advanced_security_purchased?
      return false unless business.admins.include?(user)
      true
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T::Boolean)
    end
    def self.has_rejected_request?(repository:, alert_number:)
      find_rejected_request(repository:, alert_number:).present?
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T::Boolean)
    end
    def self.has_pending_request?(repository:, alert_number:)
      return false unless CodeScanning::AlertDismissalService.new(repository).delegated_dismissal_enabled?
      find_pending_request(repository:, alert_number:).present?
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T::Boolean)
    end
    def self.is_open?(repository:, alert_number:)
      response = GitHub::Turboscan.alert(
        repository_id: repository.id,
        number: alert_number,
      )

      if response&.error&.code == :not_found
        raise AlertNotFoundError, "Alert was not found"
      end

      if response.blank? || response.error.present? || response.data.blank? || response.data.result.blank?
        GitHub.logger.info(
          "Failed to find the alert to check its resolution state",
          error: response&.error,
          "code.function": __method__.to_s,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert.numbers": alert_number,
        )
        raise AlertDismissalError, "Failed to find the alert"
      end

      alert = T.must(response.data.result)

      alert.resolution == :NO_RESOLUTION
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T::Boolean)
    end
    def self.is_dismissed?(repository:, alert_number:)
      !is_open?(repository:, alert_number:)
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T.nilable(Exemptions::ExemptionRequest))
    end
    def self.find_pending_request(repository:, alert_number:)
      request = find_request_by_alert_number(repository:, alert_number:)
      request if request&.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T.nilable(Exemptions::ExemptionRequest))
    end
    def self.find_rejected_request(repository:, alert_number:)
      request = find_request_by_alert_number(repository:, alert_number:)
      request if request&.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Rejected
    end

    sig do
      params(
        repository: Repository,
        request_id: Integer,
      ).returns(T.nilable(Exemptions::ExemptionRequest))
    end
    def self.find_request_by_id(repository:, request_id:)
      Exemptions::ExemptionRequest.for_source(repository).find_by(request_type: EXEMPTION_REQUEST_TYPE, id: request_id)
    end

    sig do
      params(
        repository: Repository,
        request_number: Integer,
      ).returns(T.nilable(Exemptions::ExemptionRequest))
    end
    def self.find_request_by_number(repository:, request_number:)
      Exemptions::ExemptionRequest.for_source(repository).find_by(number: request_number)
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
      ).returns(T.nilable(Exemptions::ExemptionRequest))
    end
    def self.find_request_by_alert_number(repository:, alert_number:)
      Exemptions::ExemptionRequest.for_source(repository).where(
        request_type: EXEMPTION_REQUEST_TYPE,
        resource_identifier: resource_identifier(repository:, alert_number:)
      ).order(created_at: :desc).first
    end

    sig do
      params(
        repository: Repository,
        alert_numbers: T::Array[Integer],
        resolution: Integer,
        resolver: User,
        resolution_note: T.nilable(String),
        pr_review_thread_id: T.nilable(Integer),
        campaign_id: T.nilable(Integer),
        reviewer: T.nilable(User),
        refresh_reason: T.nilable(Symbol),
      ).returns(T.untyped)
    end
    def self.close_alerts(repository:, alert_numbers:, resolution:, resolver:, resolution_note: nil, pr_review_thread_id: nil, campaign_id: nil, reviewer: nil, refresh_reason: :ui_alert_update)
      return [] if alert_numbers.empty?

      set_alerts_status_options = {
        repository_id: repository.id,
        numbers: alert_numbers,
        resolution: resolution,
        resolver_id: resolver.id,
        resolver_login: resolver.display_login,
        resolution_note: resolution_note,
        dismissal_approver_id: reviewer&.id,
        dismissal_approver_login: reviewer&.display_login,
      }
      response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, repository)
      if response&.error&.code == :not_found
        raise AlertNotFoundError, "Alert was not found"
      elsif response.blank? || response.error.present?
        GitHub.logger.info(
          "Failed to close the alerts",
          error: response&.error,
          "code.function": __method__.to_s,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert.numbers": alert_numbers,
        )
        raise AlertDismissalError, "Failed to close the alerts"
      end

      repository.refresh_code_scanning_status(alert_numbers:, refresh_reason:)

      if pr_review_thread_id.present?
        begin
          resolve_pr_review_thread(repository:, pr_review_thread_id:, alert_number: T.must(alert_numbers.first))
        rescue => e
          GitHub.logger.error(
            "Failed to resolve the PR review thread after closing the alert",
            exception: e,
            "code.function": __method__.to_s,
            "gh.repo.id": repository.id,
            "gh.code_scanning.alert.number": alert_numbers.first,
            "gh.pull_request.review_thread.id": pr_review_thread_id,
          )
        end
      end

      if campaign_id.present?
        analytics_event(
          actor: resolver,
          category: "security_campaigns",
          action: "close_alerts",
          label: {
            "security_campaign_id": campaign_id,
            "resolution": resolution,
            "alert_numbers_count": alert_numbers.size
          }
        )
      end

      response.data.results
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
        resolver: User,
        refresh_reason: Symbol,
      ).returns(T.untyped)
    end
    def self.open_alert(repository:, alert_number:, resolver:, refresh_reason: :ui_alert_update)
      alert_numbers = [alert_number]

      set_alerts_status_options = {
        repository_id: repository.id,
        numbers: alert_numbers,
        resolution: :NO_RESOLUTION,
        resolver_id: resolver.id,
        resolver_login: resolver.display_login,
      }
      response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, repository)
      if response&.error&.code == :not_found
        raise AlertNotFoundError, "Alert was not found"
      elsif response.blank? || response.error.present?
        GitHub.logger.info(
          "Failed to open the alerts",
          error: response&.error,
          "code.function": __method__.to_s,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert.numbers": alert_numbers,
        )
        raise AlertDismissalError, "Failed to open the alerts"
      end

      alert = response.data.results.first

      repository.refresh_code_scanning_status(alert_numbers:, refresh_reason:)

      alert
    end

    # Method copied from app/controllers/application_controller/analytics_dependency.rb as that helper can only be used
    # by controllers
    sig do
      params(
        actor: T.untyped,
        category: T.untyped,
        action: T.untyped,
        label: T.untyped
      )
      .void
    end
    private_class_method def self.analytics_event(actor:, category:, action:, label: nil)
      return if GitHub.enterprise?

      stringify_ga_label = -> (label_content) do
        return label_content.presence unless label_content.is_a?(Hash)
        label_content.map { |key, value| "#{key}:#{value}" }.join("; ")
      end

      event_params = {
        actor: actor,
        category: category,
        action: action,
        label: stringify_ga_label.call(label),
      }

      GlobalInstrumenter.instrument("analytics.event", event_params)
    end

    sig do
      params(
        repository: Repository,
        pr_review_thread_id: Integer,
        alert_number: Integer,
      ).void
    end
    private_class_method def self.resolve_pr_review_thread(repository:, pr_review_thread_id:, alert_number:)
      thread = PullRequestReviewThread.find_by(repository_id: repository.id, id: pr_review_thread_id)
      return unless thread&.conversation?

      code_scanning_app = Apps::Privileged.integration(:code_scanning) or fail "code scanning integration not installed!"
      ActiveRecord::Base.connected_to(role: :writing) do
        thread.resolve(resolver: code_scanning_app.bot)
      end
      GitHub.logger.info(
        "Autoresolving conversation for dismissed code scanning alert",
        "code.function": __method__.to_s,
        "gh.repo.id": repository.id,
        "gh.code_scanning.alert.number": alert_number,
        "gh.pull_request.review_thread.id": pr_review_thread_id,
      )
    end
  end
end
