# typed: true
# frozen_string_literal: true

module Dependabot
  module DelegatedAlertDismissal
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ApplicationController }

    private

    sig { params(alerts: T.any(Integer, T::Array[RepositoryVulnerabilityAlert], ActiveRecord::Relation), reason: String, comment: T.nilable(String)).returns(T::Boolean) }
    def handle_closure_request_creation(alerts, reason, comment)
      if alerts.is_a?(Integer)
        if current_repository
          alert_number = alerts
          repository = T.must(current_repository)
          alert = repository.repository_vulnerability_alerts.find_by(number: alert_number)
        else
          # Organization controller: integer is an alert ID
          alert = RepositoryVulnerabilityAlert.find_by(id: alerts)
        end

        if alert.nil?
          flash[:error] = "Alert not found"
          return false
        end

        alerts = [alert]
      end

      requests_created = T.let(0, Integer)
      errors = T.let([], T::Array[String])

      # Iterate through alerts collection
      alerts.each do |alert|
        success, error_message = create_closure_request_for_alert(alert, reason, comment)
        if success
          requests_created += 1
        elsif error_message
          errors << error_message
        end
      end

      flash.clear
      if requests_created > 0
        message = if requests_created == 1
          "Dismissal request created successfully"
        else
          "Created #{requests_created} dismissal requests for review."
        end
        flash[:notice] = message
      end

      if errors.any?
        # Show first error as representative
        flash[:error] = errors.first
      end

      requests_created > 0
    end

    sig { params(alert: RepositoryVulnerabilityAlert, reason: String, comment: T.nilable(String)).returns([T::Boolean, T.nilable(String)]) }
    def create_closure_request_for_alert(alert, reason, comment)
      repository = alert.repository
      if repository.nil?
        return [false, "Alert #{alert.number}: Repository not found"]
      end

      # In repository context, permissions are already checked by the controller
      if respond_to?(:current_organization, false) && T.unsafe(self).current_organization
        unless repository.can_view_vulnerability_alerts?(current_user)
          return [false, "Alert #{alert.number}: No permission to access repository #{repository.full_name}"]
        end

        unless repository.can_resolve_vulnerability_alerts?(current_user)
          return [false, "Alert #{alert.number}: No permission to request dismissal for repository #{repository.full_name}"]
        end
      end

      # For organization context, we need to create repository-specific delegated closures instances
      repo_delegated_closures = Dependabot::SecurityProduct::DelegatedClosures.new(repository)

      user = T.must(current_user)
      unless repo_delegated_closures.user_can_request_closure?(user)
        return [false, "Alert #{alert.number}: No permission to create dismissal request for repository #{repository.full_name}"]
      end

      begin
        repo_delegated_closures.create_alert_closure_request(
          user,
          alert.number.to_s,
          reason,
          comment || ""
        )
        [true, nil]
      rescue ArgumentError => e
        [false, "Alert #{alert.number}: #{e.message}"]
      rescue StandardError => e
        log_closure_request_error("Error creating dismissal request", e, alert.number)
        [false, "Alert #{alert.number}: There was an issue creating the dismissal request"]
      end
    end

    sig { params(exemption_request: T.untyped, action_type: String, comment: T.nilable(String)).returns(T::Boolean) }
    def handle_closure_request_review(exemption_request, action_type, comment)
      begin
        response, error = delegated_closures.review_exemption_request!(
          exemption_request: exemption_request,
          status: action_type,
          message: comment,
          user: T.must(current_user)
        )

        if error
          flash[:error] = error
          false
        else
          action_text = action_type == "approve" ? "approved" : "rejected"
          flash[:notice] = "Dismissal request #{action_text} successfully"
          true
        end
      rescue StandardError => e
        log_closure_request_error("Error reviewing dismissal request", e, exemption_request.id, action_type)
        flash[:error] = "There was an issue reviewing the dismissal request. Please try again."
        false
      end
    end

    def find_exemption_request!(request_id, alert_number = nil)
      exemption_request = Exemptions::ExemptionRequest.find_by(
        id: request_id,
        repository: current_repository,
        request_type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      )

      unless exemption_request
        flash[:error] = "Dismissal request not found"
        return nil
      end

      exemption_request
    end

    # For cancel operations
    def find_user_exemption_request!(request_id)
      exemption_request = Exemptions::ExemptionRequest.find_by(
        id: request_id,
        repository: current_repository,
        request_type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
        requester: current_user
      )

      unless exemption_request
        flash[:error] = "Dismissal request not found"
        return nil
      end

      exemption_request
    end

    def handle_exemption_request_cancellation(exemption_request)
      begin
        exemption_request.cancelled!
        flash[:notice] = "Dismissal request cancelled successfully"
        true
      rescue StandardError => e
        log_closure_request_error("Error cancelling dismissal request", e, exemption_request.id)
        flash[:error] = "There was an issue cancelling the dismissal request. Please try again."
        false
      end
    end

    sig { params(resource: T.nilable(T.any(Organization, Repository))).returns(T::Boolean) }
    def alert_dismissal_requests_enabled?(resource = nil)
      resource ||= T.unsafe(self).current_organization || current_repository
      ::Dependabot::SecurityProduct::DelegatedClosures.dependabot_alert_dismissal_requests_for?(resource)
    end

    sig { returns(Dependabot::SecurityProduct::DelegatedClosures) }
    def delegated_closures
      resource = T.must(current_repository || T.unsafe(self).current_organization)
      @delegated_closures ||= T.let(
        Dependabot::SecurityProduct::DelegatedClosures.new(resource),
        T.nilable(Dependabot::SecurityProduct::DelegatedClosures)
      )
      T.must(@delegated_closures)
    end

    def validate_comment_length!(comment, redirect_path = nil)
      return true unless comment
      return true if comment.length <= Dependabot::AlertDependency::STATE_CHANGE_COMMENT_MAX_LENGTH

      flash[:error] = "Comment is too long"
      false
    end

    def log_closure_request_error(message, error, *additional_data)
      log_data = {
        "error": error.message,
        "error_class": error.class.name,
        "backtrace": error.backtrace&.first(5),
        "repo_id": current_repository&.id,
        "user_id": current_user&.id,
      }

      # Add additional context data
      case additional_data.length
      when 1
        log_data["request_id_or_alert_number"] = additional_data[0]
      when 2
        log_data["request_id"] = additional_data[0]
        log_data["action_type"] = additional_data[1]
      end

      GitHub.logger.error("DependabotDelegatedAlertClosures: #{message}", **log_data)
    end
  end
end
