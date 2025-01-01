# typed: strict
# frozen_string_literal: true

module Exemptions
  class ExemptionResponse < ApplicationRecord::Domain::Repositories
    extend T::Sig
    include Instrumentation::Model

    belongs_to :exemption_request, class_name: "Exemptions::ExemptionRequest"
    belongs_to :reviewer, class_name: "User"

    validates_presence_of :exemption_request, :reviewer
    validate :validate_reviewer
    validate :validate_existing, on: :create

    after_commit :run_after_commit_callbacks, on: [:create, :update]

    STATUSES = T.let({
      approved: 0,
      rejected: 1,
      dismissed: 2,
    }.with_indifferent_access.freeze, T::Hash[T.any(Symbol, String), Integer])
    enum :status, STATUSES

    sig { params(request: ExemptionRequest, reviewer: User).returns(ExemptionResponse) }
    def self.approve!(request, reviewer)
      existing_response = request.responses.where(reviewer: reviewer).first
      if existing_response
        existing_response.approved!
        existing_response
      else
        create!(exemption_request: request, reviewer: reviewer, status: STATUSES[:approved])
      end
    end

    sig { params(request: ExemptionRequest, reviewer: User).returns(ExemptionResponse) }
    def self.reject!(request, reviewer)
      existing_response = request.responses.where(reviewer: reviewer).first
      if existing_response
        existing_response.rejected!
        existing_response
      else
        create!(exemption_request: request, reviewer: reviewer, status: STATUSES[:rejected])
      end
    end

    private

    # Only valid approvers can approve/reject the exemption request
    # Reviewer cannot be requester
    sig { void }
    def validate_reviewer
      return if exemption_request&.is_valid_reviewer?(T.must(reviewer))

      errors.add(:reviewer, "is not a valid reviewer for this request")
    end

    sig { void }
    def validate_existing
      return unless exemption_request&.responses&.exists?(reviewer: reviewer)

      errors.add(:reviewer, "has already reviewed this request")
    end

    # https://guides.rubyonrails.org/active_record_callbacks.html#transactional-callback-ordering
    # https://github.com/rails/rails/pull/46992
    # In Rails 7.1 this should have been fixed, but we must not be overriding the default configuration
    # For that reason, we are explicit about the call order
    sig { void }
    def run_after_commit_callbacks
      update_request_on_reject_or_dismiss
      send_notification
      instrument_event
    end

    sig { void }
    def update_request_on_reject_or_dismiss
      if rejected?
        exemption_request&.update(status: :rejected)
      elsif dismissed? && exemption_request&.responses&.where(status: STATUSES[:rejected])&.size == 0
        exemption_request&.update(status: :pending)
      end
    end

    sig { void }
    def send_notification
      request = T.must(exemption_request)

      return unless request.repository&.delegated_bypass_notifications_enabled?
      return unless request.request_type == "push_ruleset_bypass" || request.request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE

      notification_configuration = request.evaluator&.response_notification_configuration(request)
      return if notification_configuration.nil?

      ExemptionRequestMailer.request_status_changed(
        request,
        self,
        notification_configuration[:subject],
        notification_configuration[:reason],
        notification_configuration[:permalink],
      ).deliver_later
    end

    sig { void }
    def instrument_event
      event = case
      when approved?
        :approve
      when rejected?
        :reject
      when dismissed?
        :dismiss
      end
      # Webhook instrumentation
      instrument event, prefix: "exemption_response", exemption_response_id: id, exemption_request_id: exemption_request_id, request_type: T.must(exemption_request).request_type if event
      # Hydro instrumentation
      GlobalInstrumenter.instrument("exemption_response.#{event}",
        exemption_response: self,
        actor: reviewer,
      )
    end
  end
end
