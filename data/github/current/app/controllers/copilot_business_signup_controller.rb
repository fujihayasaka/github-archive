# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupController < ApplicationController
  include Signups::CustomContentDependency
  include WithParameterValidation

  PAGE_SIZE = 7

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::NotificationsEntries,
                      only: [:index]

  before_action :redirect_to_signup
  before_action :dotcom_required
  before_action :add_csp_exceptions
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  layout :signups_layout

  javascript_bundle "signup"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url]
  }

  def index
    benefit = extract_with_param(params)
    has_organization = user_owned_orgs.any?
    has_entities = has_organization || user_owned_businesses.any?

    custom_page = custom_page_param || "get-started"
    if !params.key?(:new) && has_entities
      render "signup/select_org_business", locals: {
        title: title,
        custom_page: custom_page,
        contentful_custom_content_entry: contentful_custom_content_entry(custom_page),
        get_started_url: get_started_url,
        get_started_link_text: get_started_link_text,
        get_started_title: get_started_title,
        get_started_text_body: get_started_text_body,
        with_param: benefit,
        is_logged_in: logged_in?,
        has_organization: has_entities
      }
    elsif (benefit == "enterprise" || benefit == "enterprise-and-ado") && !has_entities
      redirect_to enterprise_trial_accounts_new_path(with: benefit)
    else
      render "signup/new_org_business", locals: {
        title: title,
        custom_page: custom_page,
        contentful_custom_content_entry: contentful_custom_content_entry(custom_page),
        with_param: benefit,
        is_logged_in: logged_in?,
        has_organization: has_entities
      }
    end
  end

  def create
    account = if params[:type] == "business"
      Business.find_by(slug: params[:account])
    elsif params[:type] == "org"
      org = Organization.find_by_login(params[:account])
      return redirect_to get_started_url unless org
      return redirect_to with_param_to_url(org, params)
    else
      return redirect_to get_started_url
    end

    # This shouldn't happen but added in case someone manually edits the account param or gets here in Proxima
    unless account
      return redirect_to get_started_url
    end

    benefit = extract_and_validate_intent(params)
    if benefit
      BusinessIntent.create_or_update_intent(business: T.must(account), intent: benefit)
    end
    redirect_to with_param_to_url(T.must(account), params)
  end

  private

  memoize def user_owned_orgs
    current_user.owned_or_billing_manager_organizations
  end

  memoize def user_owned_businesses
    current_user.businesses(membership_type: :admin)
  end

  def title
    benefit = extract_with_param(params)
    "Get started#{benefit.present? ? " with #{benefit.gsub("-", " ").titleize}" : ""}"
  end

  def redirect_to_signup
    redirect_to signup_path(get_started_with: extract_with_param(params), return_to: request.url) unless logged_in?
  end

  def user_has_entities?
    user_owned_orgs.any? || user_owned_businesses.any?
  end

  def signups_layout
    "layouts/get_started"
  end

  def get_started_url
    benefit = extract_with_param(params)
    if benefit == "enterprise-and-ado" || benefit == "enterprise"
      return "/account/enterprises/new?with=#{benefit}"
    end
    base_url = "/get_started?new"
    return "#{base_url}&with=#{benefit}" if benefit.present?
    base_url
  end

  def get_started_link_text
    benefit = extract_with_param(params)
    if benefit == "enterprise-and-ado" || benefit == "enterprise"
      return "create a new enterprise account"
    end
    "create a new organization or enterprise account"
  end

  def get_started_title
    benefit = extract_with_param(params)
    product_name = case benefit
    when "enterprise-and-ado", "enterprise"
      "GitHub Enterprise"
    when "advanced-security"
      "GitHub Advanced Security"
    when "code-security"
      "GitHub Code Security"
    when "secret-protection"
      "GitHub Secret Protection"
    when "copilot-business"
      "Copilot Business"
    else
      "premium features"
    end
    "Choose the organization or enterprise where you want to use #{product_name}"
  end

  def get_started_text_body
    benefit = extract_with_param(params)
    product_name, action = case benefit
    when "enterprise-and-ado", "enterprise"
      ["GitHub Enterprise", "from which you'll build your enterprise"]
    when "advanced-security"
      ["GitHub Advanced Security", "in which you'll protect your code"]
    when "code-security"
      ["GitHub Code Security", "in which you'll protect your code"]
    when "secret-protection"
      ["GitHub Secret Protection", "in which you'll protect your code"]
    when "copilot-business"
      ["Copilot Business", "in which you'll protect your code"]
    else
      ["GitHub's premium features", "in which you'll utilize them"]
    end
    "Before you can use #{product_name}, you need to choose the enterprise or organization account #{action}. You can also"
  end
end
