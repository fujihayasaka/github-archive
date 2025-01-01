# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AlertDismissalService
    EXEMPTION_REQUEST_TYPE = "code_scanning_alert_dismissal"

    sig do
      params(
        repository: Repository,
        requester: RuleEngine::Types::Actor,
        alert_number: Integer,
        resolution: Integer,
        resolution_note: T.nilable(String),
      ).returns(T::Boolean)
    end
    def self.request_dismissal(repository:, requester:, alert_number:, resolution:, resolution_note:)
      existing_requests = Exemptions::ExemptionRequest.where(
        request_type: EXEMPTION_REQUEST_TYPE,
        repository: repository,
        resource_identifier: resource_identifier(repository:, alert_number:),
      ).all

      pending_requests = existing_requests.filter { |request| request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending }
      return false unless pending_requests.empty?

      Exemptions::ExemptionRequest.create!(
        resource_owner: repository,
        requester: requester,
        repository: repository,
        resource_identifier: resource_identifier(repository:, alert_number:),
        request_type: EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "resolution": "#{resolution}",
          "alert_number": "#{alert_number}",
        },
        requester_comment: resolution_note,
      )

      true
    end

    sig do
      params(
        repository: Repository,
        reviewer: User,
        request_id: Integer,
      ).returns(T::Boolean)
    end
    def self.approve_request(repository:, reviewer:, request_id:)
      request = Exemptions::ExemptionRequest.find_by(
        request_type: EXEMPTION_REQUEST_TYPE,
        id: request_id,
      )
      return false unless request&.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending

      Exemptions::ExemptionResponse.approve!(T.must(request), reviewer)

      alert_number = request&.metadata["alert_number"].to_i
      resolution = request&.metadata["resolution"].to_i
      resolver = T.must(request&.requester)
      resolution_note = request&.requester_comment
      pr_review_thread_id = request&.metadata[:pr_review_thread_id]
      close_alert(repository:, alert_number:, resolution:, resolver:, resolution_note:, pr_review_thread_id:)
    end

    sig do
      params(
        repository: Repository,
        reviewer: User,
        request_id: Integer,
      ).returns(T::Boolean)
    end
    def self.reject_request(repository:, reviewer:, request_id:)
      request = Exemptions::ExemptionRequest.where(
        request_type: EXEMPTION_REQUEST_TYPE,
        id: request_id,
      ).first

      return false unless request && request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending

      Exemptions::ExemptionResponse.reject!(request, reviewer)
      true
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer
      ).returns(T::Array[T.untyped])
    end
    def self.get_timeline_events(repository:, alert_number:)
      []
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

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
        resolution: Integer,
        resolver: User,
        resolution_note: T.nilable(String),
        pr_review_thread_id: T.nilable(Integer),
      ).returns(T::Boolean)
    end
    private_class_method def self.close_alert(repository:, alert_number:, resolution:, resolver:, resolution_note:, pr_review_thread_id:)
      alert_numbers = [alert_number]

      set_alerts_status_options = {
        repository_id: repository.id,
        numbers: alert_numbers,
        resolution: resolution,
        resolver_id: resolver.id,
        resolution_note: resolution_note,
      }

      response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, repository)
      if response.blank? || response.error.present?
        GitHub.logger.info(
          "Failed to close the alert",
          "code.function": __method__.to_s,
          "controller.name": self.class.name,
          "gh.repo.id": repository.id,
          "gh.code_scanning.alert.number": alert_number,
        )
        return false
      end

      repository.refresh_code_scanning_status(alert_numbers: alert_numbers, refresh_reason: :ui_alert_update)

      if pr_review_thread_id.present?
        resolve_pr_review_thread(repository:, pr_review_thread_id:, alert_number:)
      end

      true
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
        "controller.name": self.class.name,
        "gh.repo.id": repository.id,
        "gh.code_scanning.alert.number": alert_number,
        "gh.pull_request.review_thread.id": pr_review_thread_id,
      )
    end

  end
end
