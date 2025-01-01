# typed: true
# frozen_string_literal: true

class Oauth::IdentityManagement::SingleSignOnComponent < ApplicationComponent
  include AvatarHelper
  include SudoHelper

  renders_one :footer
  renders_one :shared_flash

  def initialize(application:, cap_authorized_saml_organizations:, cap_unauthorized_saml_organizations:, form_data: nil, return_to_url:, suggested_org: nil)
    @application = application

    @cap_authorized_saml_organizations   = cap_authorized_saml_organizations
    @cap_unauthorized_saml_organizations = cap_unauthorized_saml_organizations

    @form_data     = form_data
    @return_to_url = return_to_url
    @suggested_org = suggested_org
  end

  def initiate_sso_url_for(org)
    options = { return_to: @return_to_url }
    target  = org.external_identity_session_owner

    case target
    when ::Business
      idm_saml_initiate_enterprise_path(target, options)
    when ::Organization
      org_idm_saml_initiate_path(target, options)
    end
  end

  memoize def organizations
    @organizations = {}

    @cap_authorized_saml_organizations.each do |target|
      @organizations[target] = true
    end

    @cap_unauthorized_saml_organizations.each do |target|
      @organizations[target] = false
    end

    @organizations.sort_by { |org, _authorized| org.safe_profile_name }

    if @suggested_org.present?
      @organizations.keep_if { |org, _authorized| org == @suggested_org }
    end

    @organizations
  end
end
