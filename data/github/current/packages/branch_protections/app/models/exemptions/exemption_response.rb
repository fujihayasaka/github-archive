# typed: strict
# frozen_string_literal: true

module Exemptions
  class ExemptionResponse < ApplicationRecord::Repositories
    include Instrumentation::Model

    include ApplicationRecord::Sharding
    configure_sharding(sharding_key: :repository_id, should_shard: -> (_, _) { true })

    belongs_to :exemption_request, -> (response) { where(repository_id: response.repository_id) },
     class_name: "Exemptions::ExemptionRequest"
    belongs_to :reviewer, class_name: "User"

    validates_presence_of :exemption_request, :reviewer
    validate :validate_reviewer
    validate :validate_existing, on: :create

    before_create :copy_repository_id_from_exemption_request

    after_commit :run_after_commit_callbacks, on: [:create, :update]

    STATUSES = T.let({
      approved: 0,
      rejected: 1,
      dismissed: 2,
    }.with_indifferent_access.freeze, T::Hash[T.any(Symbol, String), Integer])
    enum :status, STATUSES

    sig { params(request: ExemptionRequest, reviewer: User, message: T.nilable(String)).returns(ExemptionResponse) }
    def self.approve!(request, reviewer, message: nil)
      message = nil unless message.present? && !message.strip.empty?
      response = request.responses.where(reviewer:).first
      if response
        response.approved!
        response.message = message
        response.save
      else
        response = create!(exemption_request: request, reviewer:, status: STATUSES[:approved], message: message)
      end
      request.evaluator&.post_approval_action(request, reviewer)
      response
    end

    sig { params(request: ExemptionRequest, reviewer: User, message: T.nilable(String)).returns(ExemptionResponse) }
    def self.reject!(request, reviewer, message: nil)
      message = nil unless message.present? && !message.strip.empty?
      existing_response = request.responses.where(reviewer: reviewer).first
      if existing_response
        existing_response.rejected!
        existing_response.message = message
        existing_response.save
        existing_response
      else
        create!(exemption_request: request, reviewer: reviewer, status: STATUSES[:rejected], message: message)
      end
    end

    sig { void }
    def copy_repository_id_from_exemption_request
      self.repository_id = exemption_request&.repository_id
    end

    private

    # Only valid approvers can approve/reject the exemption request
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
      elsif dismissed? && exemption_request&.responses&.where(status: STATUSES[:rejected], repository_id: exemption_request&.repository_id)&.size == 0
        exemption_request&.update(status: :pending)
      end
    end

    sig { void }
    def send_notification
      request = T.must(exemption_request)

      return unless ExemptionRequestEmailJob::PERFORM_REQUEST_TYPES.include?(request.request_type)

      notification_configuration = request.evaluator&.response_notification_configuration(request)
      return if notification_configuration.nil?

      if request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE ||
         request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
        ExemptionRequestMailer.alert_dismissal_request_status_changed(
          request_or_mailer_hash(request),
          response_or_mailer_hash(self),
          notification_configuration[:subject],
          notification_configuration[:reason],
          notification_configuration[:permalink],
        ).deliver_later
      else
        ExemptionRequestMailer.request_status_changed(
          request_or_mailer_hash(request),
          response_or_mailer_hash(self),
          notification_configuration[:subject],
          notification_configuration[:reason],
          notification_configuration[:permalink],
        ).deliver_later
      end
    end

    sig { params(request: Exemptions::ExemptionRequest).returns(T.any(T::Hash[Symbol, Integer], Exemptions::ExemptionRequest)) }
    def request_or_mailer_hash(request)
      { id: request.id, repository_id: request.repository_id }
    end

    sig { params(response: Exemptions::ExemptionResponse).returns(T.any(T::Hash[Symbol, Integer], Exemptions::ExemptionResponse)) }
    def response_or_mailer_hash(response)
      { id: response.id, repository_id: exemption_request&.repository_id }
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

      instrument_data = {
        prefix: "exemption_response",
        exemption_response_id: id,
        exemption_request_id: exemption_request_id,
        repository_id: repository_id
      }

      # Webhook instrumentation
      instrument event, **instrument_data, request_type: T.must(exemption_request).request_type if event
      # Hydro instrumentation
      GlobalInstrumenter.instrument("exemption_response.#{event}",
        exemption_response: self,
        actor: reviewer,
      )
    end
  end
end
