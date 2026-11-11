# typed: true
# frozen_string_literal: true

class Site::ContactController < Site::BaseController
  include EscapeHelper

  skip_before_action :disable_in_enterprise_and_proxima

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:index]

  # Used for the "Contact us" page, which now redirects to support.github.com
  def index
    params[:form] ||= {}
    params[:flavor] ||= "default"

    return render("site/contact/index") if GitHub.single_business_environment?

    # render static DMCA page
    return render("site/contact/index") if params[:flavor] == "dmca"

    # reported_content is a user profile, redirect to report-abuse
    if reported_user && reported_content == "#{GitHub.scheme}://#{GitHub.host_name}/#{reported_user.display_login}"
      return redirect_to flavored_contact_path(flavor: "report-abuse", report: "#{reported_user.display_login} (user)")
    end

    # Redirect to support.github.com
    if %w( report-abuse report-content ).include?(params[:flavor])
      category = params[:flavor]
      report_content_url = safe_onsite_uri(reported_content) if reported_content
      report, report_id, report_type = if reported_content
        [reported_user.display_login, reported_user.id, "content"]
      elsif reported_action
        [reported_action.name, nil, "action"]
      elsif reported_app
        [reported_app.name, reported_app.id, "app"]
      elsif reported_user
        [reported_user.display_login, reported_user.id, "user"]
      elsif category == "report-abuse" && params[:report].present?
        [params[:report], nil, "unspecified"]
      else
        ["other", nil, "unspecified"]
      end

      form_params = {
        category: category,
        report: report,
        report_id: report_id,
        report_type: report_type,
        report_content_url: report_content_url
      }.compact

      redirect_to "#{GitHub.contact_support_url}/report-abuse?#{form_params.to_query}"
    else
      # Send DMCA, privacy, and reinstatement concerns directly to the HelpHub contact form,
      # rather than the landing page.
      helphub = case params[:flavor]
      when "dmca-notice"
        "#{GitHub.contact_support_url}/dmca-takedown"
      when "dmca-counter-notice"
        "#{GitHub.contact_support_url}/dmca-counter-notice"
      when "privacy"
        "#{GitHub.contact_support_url}/privacy"
      when "reinstatement"
        "#{GitHub.contact_support_url}/reinstatement"
      else
        GitHub.contact_support_url
      end

      # Include prefilled subject & comments when redirecting to HelpHub, if present.
      form_params = {
        subject: params.dig(:form, :subject),
        comments: params.dig(:form, :comments),
      }.compact

      if form_params.present?
        contact_params = { form: form_params }
        contact_params[:tags] = ["dotcom-contact-params", params.dig(:form, :tags) || params.dig(:tags)].compact.join(",")
        helphub += "?#{contact_params.to_query}"
      elsif helphub.end_with?("/contact")
        helphub = "#{GitHub.support_url}?tags=dotcom-direct"
      end

      redirect_to helphub, status: form_params.present? ? 302 : 301
    end
  end

  private

  def reported_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @reported_user if @reported_user
    flavor = (params[:flavor] || params[:form][:flavor])
    return unless %w(report-abuse report-content).include?(flavor)
    report_string = params[:report] || params[:form][:report]
    if report_string =~ /\A([^ ]+)( \((user|comment)\))?\z/
      @reported_user = User.find_by_login($1)
    end
  end

  def reported_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @reported_app if @reported_app
    return unless (params[:flavor] || params[:form][:flavor]) == "report-abuse"
    report_string = params[:report] || params[:form][:report]
    if report_string =~ /\A(.+) \(app\)/
      @reported_app = Integration.find_by(name: $1)
    end
  end

  def reported_action # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @reported_action if @reported_action
    return unless (params[:flavor] || params[:form][:flavor]) == "report-abuse"
    report_string = params[:report] || params[:form][:report]
    if report_string =~ /\A(.+) \(GitHub Action\)\z/
      @reported_action = RepositoryAction.find_by(name: $1)
    end
  end

  def reported_content
    return unless (params[:flavor] || params[:form][:flavor]) == "report-content"
    content_url = params[:content_url] || params[:form][:content_url]
    content_url.to_s if reported_user && content_url
  end
end
