# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %w(index)
  before_action :check_for_owners, only: %w(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/organizations", locals: {
      business: this_business,
      organizations: this_business
        .filtered_organizations(query: params[:query])
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end

  def create
    org = organization_from_param
    unless org
      flash[:error] = "Organization #{params[:organization]} does not exist."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    if this_business.organizations.include? org
      flash[:notice] = "Organization #{org.login} is already associated with #{this_business.name}."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    if this_business.enterprise_managed_user_enabled?
      flash[:error] = "#{this_business} is an externally managed enterprise. Please advise the enterprise owner to create a new organization."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    if this_business.two_factor_requirement_enabled? && !org.two_factor_requirement_enabled? && org.affiliated_users_with_two_factor_disabled_exist?
      if !params.has_key?(:verify)
        flash[:error] = "Adding #{org.name} to the enterprise account requires confirming the organization's name."
        return redirect_to stafftools_enterprise_organizations_path(this_business)
      elsif org.name.downcase != params[:verify].downcase
        flash[:error] = "You must type the name of the organization to confirm."
        return redirect_to stafftools_enterprise_organizations_path(this_business)
      end
    end

    membership = this_business.add_organization(org, actor: current_user)
    if membership.valid?
      BusinessMailer.invited_organization_finalized_stafftools(org, this_business).deliver_later
      flash[:notice] = "Added organization #{org.login} and queued background job to create enterprise user accounts for organization members."
    else
      flash[:error] = "Failed to add organization #{org.login}. #{membership.errors.full_messages.to_sentence}."
    end

    redirect_to stafftools_enterprise_organizations_path(this_business)
  end

  def destroy
    org = organization_from_param
    unless org
      flash[:error] = "Organization #{params[:organization]} does not exist."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    membership = this_business.organization_memberships.where organization: org
    unless membership.any?
      flash[:error] = "Organization #{params[:organization]} doesn't belong to #{this_business.name}."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    if org.admins.empty?
      flash[:error] = "Organization #{params[:organization]} has no owners. Please add an owner and try again."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    if this_business.enterprise_managed_user_enabled?
      flash[:error] = "#{this_business} is an externally managed enterprise. Please ask the enterprise owner to delete the organization."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    this_business.remove_organization(org, actor: current_user)
    flash[:notice] = "Removed organization #{org.login}."
    redirect_to stafftools_enterprise_organizations_path(this_business)
  end

  private

  def organization_from_param
    ::Organization.find_by login: params[:organization]
  end
end
