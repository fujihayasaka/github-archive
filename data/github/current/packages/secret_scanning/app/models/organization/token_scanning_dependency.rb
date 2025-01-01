# typed: strict
# frozen_string_literal: true

module Organization::TokenScanningDependency
  extend T::Helpers
  include SecretScanning::Features::FeatureFlagHelper

  requires_ancestor { Organization }

  PUSH_PROTECTION_CUSTOM_MSG_KEY = "push-protection-custom-message"

  sig { returns(T.nilable(String)) }
  def get_push_protection_custom_message
    if config.inherited?(PUSH_PROTECTION_CUSTOM_MSG_KEY)
      return nil
    end
    config.get(PUSH_PROTECTION_CUSTOM_MSG_KEY)
  end

  sig { params(msg: T.nilable(String), updater: User).returns(T::Boolean) }
  def set_push_protection_custom_message(msg, updater)
    config.set(PUSH_PROTECTION_CUSTOM_MSG_KEY, msg, updater)
  end

  sig { params(actor: User).returns(T::Boolean) }
  def can_view_delegated_bypass_requests_list?(actor)
    T.bind(self, ::Organization)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :org_review_and_manage_secret_scanning_bypass_requests,
      actor: actor,
      subject: self
    ).then(&:allow?).sync
  end

  sig { params(actor: User).returns(T::Boolean) }
  def has_review_delegated_alert_closure_fgp?(actor)
    T.bind(self, ::Organization)
    Authz.domain.check_allowed(actor, :org_review_and_manage_secret_scanning_closure_requests, self)
  end

  sig { returns(Integer) }
  def token_scanning_bypass_request_count
    # Query for the past month, which is the max time period displayed on the list UI
    total_count = 0
    page = 1
    loop do
      requests, has_more = self.fetch_bypass_requests(request_types: [SecretScanning::Constants::EXEMPTION_REQUEST_TYPE], request_status: "open", time_period: "month", page: page)
      total_count += requests.count { |exemption| !exemption.expired? && exemption.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending }
      page += 1
      break unless has_more
    end
    total_count
  end

  sig { returns(Integer) }
  def token_scanning_closure_request_count
    # Query for the past month, which is the max time period displayed on the list UI
    total_count = 0
    page = 1
    loop do
      requests, has_more = self.fetch_bypass_requests(request_types: [SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE], request_status: "open", time_period: "month", page: page)
      total_count += requests.count { |exemption| !exemption.expired? && exemption.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending }
      page += 1
      break unless has_more
    end
    total_count
  end
end
