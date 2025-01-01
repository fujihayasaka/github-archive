# typed: false
# frozen_string_literal: true

class EditRepositories::AdminScreen::PagesCertificateStatusView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  # state passed by controller
  attr_reader :state, :cname

  # Mapping for Certificate provisioning state machine state to readable state.
  PROVISION_STATE_MAPPING = {
    requsted: [:new, :authorization_created, :authorization_pending, :authorized, :authorization_revoked, :dns_changed],
    approved: [:issued, :uploaded],
    active: [:approved],
    errored: [:errored],
    bad_authz: [:bad_authz]
  }

  # Mapping for Readable state to text.
  PROVISION_STATES = {
    requsted: "Certificate Requested",
    approved: " Certificate Approved",
    active: "Certificate Active",
    errored: "Error",
    bad_authz: "Certificate Request Error"
  }

  # The sequence path state for certificate provisioning with the error state.
  PROVISION_STEPS = [:requsted, :approved, :active]

  # The background color of the progress bar.
  def bg_color
    return "danger" if error
    return "warning" if state == :bad_authz
    "success"
  end

  # Convert state into view readable state.
  def readable_state
    PROVISION_STATES[certificate_provision_state]
  end

  # The description of current certificate provision state.
  def state_description
    return "Certificate provisioning will retry automatically in a short period, please be patient." if state == :bad_authz
    if state == :errored
      if cname
        check = GitHubPages::HealthCheck::Site.new cname
        return "#{check.reason.message}." if check && check.reason
      end
      return nil
    end
    return "The certificate has been uploaded and is awaiting activation." if state == :uploaded
    return "The certificate has been activated. Please allow for up to 30 minutes to 1 hour for it to be globally available. If you still see a privacy error, you may need to restart your browser." if state == :approved
    Page::Certificate.state_description(state.to_s)
  end

  # String to display how many steps has been executed. e.g. 2 of 8
  def progress_status
    return "#{PROVISION_STEPS.length} of #{PROVISION_STEPS.length}" if error
    return "1 of #{PROVISION_STEPS.length}" if state == :bad_authz
    "#{PROVISION_STEPS.index(certificate_provision_state) + 1} of #{PROVISION_STEPS.length}"
  end

  # The percentage of the displayed progress bar.
  def percentage
    return "100%" if state == :errored
    return "#{100.0 / PROVISION_STEPS.length}%" if state == :bad_authz
    "#{(PROVISION_STEPS.index(certificate_provision_state) + 1) * 100.0 / PROVISION_STEPS.length}%"
  end

  def error
    state == :errored
  end

  private

  def certificate_provision_state
    PROVISION_STATE_MAPPING.each do |certificate_state, states|
      return certificate_state if states.include?(state)
    end
    nil
  end
end
