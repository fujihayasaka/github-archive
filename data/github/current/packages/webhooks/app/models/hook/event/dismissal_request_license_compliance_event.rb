# typed: true
# frozen_string_literal: true

class Hook::Event::DismissalRequestLicenseComplianceEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "closure requests for License compliance alerts"

  description <<~DESC
  License compliance alert closure request was created, cancelled, or received a response (approved or rejected).
DESC

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id

  def self.feature_flagged?
    true
  end

  def self.visible_for?(_user, target)
    business = case target
    when Business then target
    when Organization then target.business
    when Repository then target.business
    end

    Permissions::LicensePolicy.is_license_compliance_enabled?(business)
  end

  def target_repository
    Repository.find_by(id: repository_id)
  end

  def feature_flag_enabled?
    Permissions::LicensePolicy.is_license_compliance_enabled?(target_business)
  end
end
