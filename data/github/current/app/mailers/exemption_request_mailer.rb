# typed: true
# frozen_string_literal: true

class ExemptionRequestMailer < ApplicationMailer
  include CodeScanningHelper

  self.mailer_name = "mailers/exemption_request"

  layout "layouts/primer_layout"

  sig do
    params(
      bypasser: User,
      request: Exemptions::ExemptionRequest,
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def push_bypass(bypasser, request, subject, reason, permalink)
    @request = request
    @repository = T.must(request.repository)
    @permalink = permalink
    @reason = reason
    @expiry_notice = expiry_notice_for(request)
    @footer_links = default_footer_links

    premail(
      from: github,
      to: GitHub.newsies.email(bypasser, @repository.owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  sig do
    params(
      bypasser: User,
      request: Exemptions::ExemptionRequest,
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def repo_policy_bypass(bypasser, request, subject, reason, permalink)
    @request = request
    @repository = T.must(request.repository)
    @permalink = permalink
    @reason = reason
    @expiry_notice = expiry_notice_for(request)
    @footer_links = default_footer_links

    premail(
      from: github,
      to: GitHub.newsies.email(bypasser, @repository.owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  sig do
    params(
      request: T.any(Exemptions::ExemptionRequest, T::Hash[Symbol, Integer]),
      response: T.any(Exemptions::ExemptionResponse, T::Hash[Symbol, Integer]),
      subject: String,
      reason: String,
      permalink: String,
      header: String
    ).void
  end
  def request_status_changed(request, response, subject, reason, permalink, header)
    request = Exemptions::ExemptionRequest.find_by!(id: request[:id], repository_id: request[:repository_id]) if request.is_a?(Hash)
    @request = request
    response = Exemptions::ExemptionResponse.find_by!(id: response[:id], repository_id: response[:repository_id]) if response.is_a?(Hash)
    @response = response
    @status = response.status == "rejected" ? "denied" : response.status
    @repository = request.repository
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links
    @header = header

    premail(
      from: github,
      to: GitHub.newsies.email(request.requester, T.must(@repository).owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  sig do
    params(
      reviewer: User,
      request: Exemptions::ExemptionRequest,
      subject: String,
      reason: String,
      permalink: String,
    ).void
  end
  def alert_dismissal_requested(reviewer, request, subject, reason, permalink)
    @request = request
    @repository = T.must(request.repository)
    @permalink = permalink
    @reason = reason
    @expiry_notice = expiry_notice_for(request)
    @footer_links = default_footer_links

    requester = request.requester
    if requester.nil?
      Failbot.report("ExemptionRequestMailer: requester is nil for exemption request", "gh.exemptions.request.id" => request.id)
      return
    end

    if request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      resolution = Turboscan::Proto::ResultResolution.lookup(request.metadata["resolution"].to_i)
      @closure_reason = alert_closure_reasons[resolution]
      @closure_detail = close_reason_details_singular[resolution]
      @title = "#{requester.display_login} would like to dismiss a code scanning alert"
    elsif request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason = request.metadata["reason"].to_sym
      @closure_reason = SecretScanning::ExemptionConstants::CLOSE_REASON_NAMES[reason]
      @closure_detail = SecretScanning::ExemptionConstants::CLOSE_REASON_DETAILS[reason]
      @title = "#{requester.display_login} would like to dismiss a secret scanning alert"
    elsif request.request_type == Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason_sym = request.metadata["reason"].to_sym
      @closure_reason = RepositoryVulnerabilityAlert::DISMISS_REASONS[reason_sym]
      @closure_detail = nil  # Dependabot doesn't have detailed descriptions like CodeScanning/SecretScanning
      @title = "#{requester.display_login} would like to dismiss a Dependabot alert"
    elsif request.request_type == DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      @closure_reason = request.metadata["reason"]&.capitalize
      @closure_detail = nil
      @title = "#{requester.display_login} would like to close a license compliance alert"
    end

    premail(
      from: github,
      to: GitHub.newsies.email(reviewer, @repository.owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{request_display_number})",
    )
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
      permalink: String
    ).void
  end
  def alert_dismissal_request_submitted_confirmation(request, permalink)
    @request = request
    @repository = T.must(request.repository)
    @permalink = permalink
    @reason = "You are receiving this email because you submitted an alert dismissal request."
    @footer_links = default_footer_links

    if request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      resolution = Turboscan::Proto::ResultResolution.lookup(request.metadata["resolution"].to_i)
      @closure_reason = alert_closure_reasons[resolution]
      @closure_detail = close_reason_details_singular[resolution]
      @title = "Your request to dismiss a code scanning alert has been submitted"
    elsif request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason = request.metadata["reason"].to_sym
      @closure_reason = SecretScanning::ExemptionConstants::CLOSE_REASON_NAMES[reason]
      @closure_detail = SecretScanning::ExemptionConstants::CLOSE_REASON_DETAILS[reason]
      @title = "Your request to dismiss a secret scanning alert has been submitted"
    elsif request.request_type == Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason_sym = request.metadata["reason"].to_sym
      @closure_reason = RepositoryVulnerabilityAlert::DISMISS_REASONS[reason_sym]
      @closure_detail = nil
      @title = "Your request to dismiss a Dependabot alert has been submitted"
    elsif request.request_type == DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      @closure_reason = request.metadata["reason"]&.capitalize
      @closure_detail = nil
      @title = "Your request to close a license compliance alert has been submitted"
    end

    premail(
      from: github,
      to: GitHub.newsies.email(request.requester, @repository.owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{@title} (##{request_display_number})",
    )
  end

  sig do
    params(
      request: T.any(Exemptions::ExemptionRequest, T::Hash[Symbol, Integer]),
      response: T.any(Exemptions::ExemptionResponse, T::Hash[Symbol, Integer]),
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def alert_dismissal_request_status_changed(request, response, subject, reason, permalink)
    request = Exemptions::ExemptionRequest.find_by!(id: request[:id], repository_id: request[:repository_id]) if request.is_a?(Hash)
    @request = request
    response = Exemptions::ExemptionResponse.find_by!(id: response[:id], repository_id: request[:repository_id]) if response.is_a?(Hash)
    @response_comment = response.message
    @status = response.status == "rejected" ? "denied" : response.status
    @repository = request.repository
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links
    @show_response_comment = false
    @header_text = "Your request to dismiss was #{@status}"

    if request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      resolution = Turboscan::Proto::ResultResolution.lookup(request.metadata["resolution"].to_i)
      @closure_reason = alert_closure_reasons[resolution].downcase
      @show_closure_reason = @closure_reason.present? && @status != "denied"
      @show_response_comment = @response_comment.present?
      @text = "Your request to dismiss this code scanning alert"
      @text += " as #{@closure_reason}" if @show_closure_reason
      @text += " was #{@status}"
      @text += " with the following comment:" if @show_response_comment
      @text += "." if !@show_response_comment
    elsif request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason = request.metadata["reason"].to_sym
      @closure_reason = SecretScanning::ExemptionConstants::CLOSE_REASON_NAMES[reason]&.downcase
      @show_closure_reason = @closure_reason.present? && @status != "denied"
      @text = "Your request to dismiss this secret scanning alert"
      @text += " as #{@closure_reason}" if @show_closure_reason
      @text += " was #{@status}."
    elsif request.request_type == Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason_sym = request.metadata["reason"].to_sym
      @closure_reason = RepositoryVulnerabilityAlert::DISMISS_REASONS[reason_sym]&.downcase
      @show_closure_reason = @closure_reason.present? && @status != "denied"
      @show_response_comment = @response_comment.present?
      @text = "Your request to dismiss this Dependabot alert"
      @text += " as #{@closure_reason}" if @show_closure_reason
      @text += " was #{@status}"
      @text += " with the following comment:" if @show_response_comment
      @text += "." if !@show_response_comment
    elsif request.request_type == DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      @header_text = "Your request to close was #{@status}"
      @closure_reason = request.metadata["reason"]
      @show_closure_reason = @closure_reason.present? && @status != "denied"
      @show_response_comment = @response_comment.present?
      @text = "Your request to close this license compliance alert"
      @text += " as #{@closure_reason}" if @show_closure_reason
      @text += " was #{@status}"
      @text += " with the following comment:" if @show_response_comment
      @text += "." if !@show_response_comment
    end

    premail(
      from: github,
      to: GitHub.newsies.email(request.requester, T.must(@repository).owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{request_display_number})",
    )
  end

  sig do
    params(
      recipient: User,
      request: T.any(Exemptions::ExemptionRequest, T::Hash[Symbol, Integer]),
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def alert_dismissal_request_cancelled(recipient, request, subject, reason, permalink)
    request = Exemptions::ExemptionRequest.find_by!(id: request[:id], repository_id: request[:repository_id]) if request.is_a?(Hash)
    @request = request
    @repository = request.repository
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links

    # Only for Dependabot dismissal requests - skip others for now
    return unless request.request_type == Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE

    reason_sym = request.metadata["reason"].to_sym
    @closure_reason = RepositoryVulnerabilityAlert::DISMISS_REASONS[reason_sym]&.downcase
    @text = "The request to dismiss this Dependabot alert"
    @text += " as \"#{@closure_reason}\"" if @closure_reason.present?
    @text += " has been cancelled."

    premail(
      from: github,
      to: GitHub.newsies.email(recipient, T.must(@repository).owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{request_display_number})",
    )
  end

  private

  def expiry_notice_for(request)
    return nil unless request.expires_at

    duration_seconds = (request.expires_at - (request.created_at || Time.zone.now)).to_i

    duration_text = if duration_seconds <= 8.days.to_i
      "7 days"
    elsif duration_seconds <= 45.days.to_i
      "30 days"
    else
      "1 year"
    end

    "This request expires in #{duration_text}. After expiry, the request will be closed and treated as denied."
  end

  def request_display_number
    if @request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      return @request.resource_identifier
    elsif @request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      return @request.metadata["alert_number"]
    elsif @request.request_type == Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      return @request.metadata["alert_number"]
    elsif @request.request_type == DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
      return @request.metadata["alert_number"]
    end
    @request.number
  end

  def default_footer_links
    [
      { url: settings_email_preferences_url, text: "Email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]
  end
end
