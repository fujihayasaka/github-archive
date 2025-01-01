# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::MemberOrganizationsController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig

  sig { void }
  def destroy
    if this_business.enterprise_managed_user_enabled?
      flash[:error] = "#{this_business} is an externally managed enterprise. Please ask the enterprise owner to delete the organizations."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    organizations = this_business.organizations
    if organizations.empty?
      flash[:error] = "#{this_business} has no organizations to remove."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    orgs_without_owners = organizations.select { |org| org.admins.empty? }
    unless orgs_without_owners.empty?
      flash[:error] = "The following organizations have no owners: #{orgs_without_owners.map(&:display_login).sort.join(', ')}. Please add an owner to each aforementioned organization and try again."
      return redirect_to stafftools_enterprise_organizations_path(this_business)
    end

    RemoveBusinessOrganizationsJob.perform_later(this_business.id, actor: current_user)

    flash[:notice] = "The organizations have been queued for removal."
    redirect_to stafftools_enterprise_organizations_path(this_business)
  end
end
