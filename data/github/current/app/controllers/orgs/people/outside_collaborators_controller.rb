# typed: true
# frozen_string_literal: true

class Orgs::People::OutsideCollaboratorsController < Orgs::Controller
  include ActionView::Helpers::TextHelper
  include EnterpriseManagedUsersHelper
  include RepositoryControllerMethods
  include Orgs::Invitations::RateLimiting

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :login_required
  before_action :organization_admin_required
  before_action only: %i(create destroy) do
    T.bind(self, Orgs::People::OutsideCollaboratorsController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end
  before_action :ensure_can_convert_to_outside_collaborators, only: :create

  javascript_bundle :organizations

  def index
    view = create_view_model(
      Orgs::People::OutsideCollaboratorsView,
      organization: this_organization,
      page: current_page,
      query: params[:query],
      finished_migration: params[:finished_migration] == "1",
      rate_limited: org_invite_rate_limited?,
    )

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "orgs/people/outside_collaborators_list", locals: { view: view }
        else
          render "orgs/people/outside_collaborators", locals: { view: view }
        end
      end
    end
  end

  def create
    member_ids = params[:member_ids].present? && params[:member_ids].split(",")
    matching_members = this_organization.visible_users_for(current_user, actor_ids: member_ids).to_a

    # Don't allow the current user to remove themself.
    if matching_members.delete(current_user)
      flash[:error] = "You can't remove yourself from the organization. Have another admin do this for you."
      return redirect_to :back
    end

    # Don't allow all admins to be removed from the org
    remaining_admins = this_organization.admins.pluck(:id) - matching_members.pluck(:id)

    if remaining_admins.empty?
      flash[:error] = "You can't remove all owners of this organization."
      return redirect_to :back
    end

    if this_organization.two_factor_requirement_enabled?
      if matching_members.any? { |m| !m.two_factor_authentication_enabled? } ||
        matching_members.any? { |m| this_organization.disallowed_two_factor_method_used_by?(m) }
        flash[:error] = "Some invalid users were selected. Members must be compliant with your organization's 2FA policy in order to be converted to an outside collaborator."
        return redirect_to :back
      end
    end

    matching_members.each do |member|
      this_organization.convert_to_outside_collaborator(member)
    end

    flash[:notice] =
      case matching_members.size
      when 0
        "Nobody was converted to an outside collaborator."
      when 1
        "You've removed #{matching_members.first.display_login} from the organization and preserved their repository access. It may take a few minutes to process."
      else
        "You've removed #{matching_members.size} people from the organization and preserved their repository access. It may take a few minutes to process."
      end

    redirect_to :back
  end

  def destroy
    users = User.where(id: Array.wrap(params[:outside_collaborator_ids]))

    count = users.size

    flash[:notice] = "You've requested removal of #{count} #{"outside collaborator".pluralize(count)}. It may take a few minutes to process."

    users.find_each do |user|
      this_organization.remove_outside_collaborator(user)
    end

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end
end
