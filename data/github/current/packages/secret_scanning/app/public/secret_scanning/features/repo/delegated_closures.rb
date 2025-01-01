# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repo level enablement for Delegated Alert Closures
  class DelegatedClosures
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_closures.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
      @org_owner_delegated_closures = nil
      if @repo.owner&.is_a?(Organization)
        @org_owner_delegated_closures = T.let(SecretScanning::Features::Org::DelegatedClosures.new(T.cast(@repo.owner, Organization)), T.nilable(SecretScanning::Features::Org::DelegatedClosures))
      end
    end

    # Indicate whether opt-in for this feature is available for this repo
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.enabled?
      return false unless SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@repo)
      true
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(user: User, closure_request: Exemptions::ExemptionRequest, alert: SecretScanning::Models::Alert).returns(T::Boolean) }
    def display_review_buttons_for_closure_request?(user, closure_request, alert)
      # The feature should be enabled
      return false unless self.enabled?
      # The corresponding alert should be open
      return false if alert.is_closed
      # The closure request shouldn't have any non-dismissed responses
      return false if closure_request.responses.any? { |response| response.status != "dismissed" }
      # TODO: replace the above check with the following check once https://github.com/github/secret-scanning/issues/9545 is done.
      # return false unless closure_request.status == Exemptions::ExemptionRequest::STATUSES[:pending]

      # The closure request should not be cancelled
      return false if closure_request.status == "cancelled"

      # The user should have review permissions, which get set at the org level
      return false unless @org_owner_delegated_closures&.user_can_review_closure_requests?(user)
      true
    end

    sig { params(user: User, closure_request: Exemptions::ExemptionRequest, alert: SecretScanning::Models::Alert).returns(T::Boolean) }
    def display_cancel_button_for_closure_request?(user, closure_request, alert)
      # The feature should be enabled
      return false unless self.enabled?
      # The corresponding alert should be open
      return false if alert.is_closed
      # The user who opened the closure request should be the one attempting to cancel it
      return false unless closure_request.requester_id == user.id
      # The closure request status should be pending
      return false unless closure_request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending

      true
    end

    sig { params(user: User).returns(T::Boolean) }
    def user_can_review_closure_requests?(user)
      return false unless self.enabled?
      return false unless @org_owner_delegated_closures&.user_can_review_closure_requests?(user)
      true
    end
  end
end
