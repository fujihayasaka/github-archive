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
    @footer_links = default_footer_links

    premail(
      from: github,
      to: GitHub.newsies.email(bypasser, @repository.owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
      response: Exemptions::ExemptionResponse,
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def request_status_changed(request, response, subject, reason, permalink)
    @request = request
    @response = response
    @status = response.status == "rejected" ? "denied" : response.status
    @repository = request.repository
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links

    premail(
      from: github,
      to: GitHub.newsies.email(request.requester, T.must(@repository).owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{@request.number})",
    )
  end

  def alert_dismissal_requested(reviewer, request, subject, reason, permalink)
    @request = request
    @repository = T.must(request.repository)
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links

    if request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      resolution = Turboscan::Proto::ResultResolution.lookup(request.metadata["resolution"].to_i)
      @closure_reason = alert_closure_reasons[resolution]
      @closure_detail = close_reason_details_singular[resolution]
      @title = "#{@request.requester.display_login} would like to dismiss a code scanning alert"
    elsif request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason = request.metadata["reason"].to_sym
      @closure_reason = SecretScanning::ExemptionConstants::CLOSE_REASON_NAMES[reason]
      @closure_detail = SecretScanning::ExemptionConstants::CLOSE_REASON_DETAILS[reason]
      @title = "#{@request.requester.display_login} would like to dismiss a secret scanning alert"
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
      response: Exemptions::ExemptionResponse,
      subject: String,
      reason: String,
      permalink: String
    ).void
  end
  def alert_dismissal_request_status_changed(request, response, subject, reason, permalink)
    @request = request
    @response = response
    @status = response.status == "rejected" ? "denied" : response.status
    @repository = request.repository
    @permalink = permalink
    @reason = reason
    @footer_links = default_footer_links

    if request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      resolution = Turboscan::Proto::ResultResolution.lookup(request.metadata["resolution"].to_i)
      @closure_reason = alert_closure_reasons[resolution].downcase
      @text = "Your request to dismiss this code scanning alert was #{@status}."
    elsif request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      reason = request.metadata["reason"].to_sym
      @closure_reason = SecretScanning::ExemptionConstants::CLOSE_REASON_NAMES[reason]&.downcase
      @text = "Your request to dismiss this secret scanning alert was #{@status}."
    end

    premail(
      from: github,
      to: GitHub.newsies.email(request.requester, T.must(@repository).owner),
      subject: "[#{T.must(@repository).name_with_display_owner}] #{subject.strip} (##{request_display_number})",
    )
  end

  private

  def request_display_number
    if @request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      return @request.resource_identifier
    elsif @request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
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
