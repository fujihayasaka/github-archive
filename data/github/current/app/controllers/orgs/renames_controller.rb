# typed: true
# frozen_string_literal: true

class Orgs::RenamesController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include Orgs::Invitations::RateLimiting
  include GitHub::RateLimitedRequest

  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  rate_limit_requests \
    if: :orgs_rate_limit_filter,
    only: :update,
    key: :rate_limit_key,
    max: 10,
    ttl: 1.hour,
    at_limit: :at_rate_limit

  def update
    GitHub.context.push({
      spamurai_form_signals: spamurai_form_signals,
    })

    org = Organization.find_by(id: current_organization.id)

    if GitHub.organization_namespacing_enabled?
      business = T.must(org).business
      params[:login] = User.standardize_login(params[:login], suffix: business.shortcode) if business.present?
    end

    if T.must(org).rename(params[:login], actor: current_user)
      render "organizations/rename", locals: { org: org }
    else
      flash[:error] = T.must(org).errors.full_messages.to_sentence
      redirect_to :back
    end
  end

  private

  def rate_limit_key
    "organizations.rename:#{current_user.id}"
  end
end
