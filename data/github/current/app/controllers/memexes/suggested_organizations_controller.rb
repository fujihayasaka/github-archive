# typed: strict
# frozen_string_literal: true

# This controller is designed to serve a specific purpose - computing the work of checking organizations
# and permissions for the current user to serve a partial HTML document to the client. This follows the conventions
# of the `Repositories::New::OwnerMenuOptionComponent` - where an owner may be selected - but the <details> element
# doesn't handle passing selected items with this partial HTML docment, so check the `CopyProjectElement` client-side
# logic for the remaining glue that allows the response from this controller to update the form state in the client.
class Memexes::SuggestedOrganizationsController < Memexes::Controller

  before_action :login_required
  before_action :require_this_memex

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    return render_404 unless this_memex.viewer_can_read?(current_user)

    return render_404 if copy_as_template && !this_memex.owner.is_a?(Organization)

    respond_to do |format|
      format.html do
        render Memex::ProjectList::CopyProjectOrganizationMenuComponent.new(
            owners: possible_new_owners,
            default_owner: possible_new_owners.first
          ),
          layout: false,
          content_type: "text/html"
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  memoize def copy_as_template
    params[:copy_as_template] == "true"
  end

  sig { returns(T.any(Organization, User)) }
  memoize def owner
    this_memex.owner
  end

  sig { returns(T::Array[T.any(Organization, User)]) }
  memoize def possible_new_owners
    options = []

    # A possible new owner is the *current* owner if the current user can write to those projects
    writable = owner.projects_enabled? && owner.projects_writable_by?(current_user)
    options << owner if writable

    # Check the copy_as_template parameter has been set in the request's querystring - this allows the viewer to
    # copy a project as a template
    options << current_user unless copy_as_template

    # Additional possible owners are the organizations the current user can write to
    writable_organizations.each do |org|
      options << org
    end

    options.uniq
  end

  # TODO: This would be better as a query rather than done in memory
  sig { returns(T::Array[Organization]) }
  def writable_organizations
    orgs = current_user.organizations | current_user.billing_manager_organizations

    orgs.select do |org|
      org.projects_enabled? && org.projects_writable_by?(current_user)
    end.sort_by { |org| org.display_login.downcase }
  end
end
