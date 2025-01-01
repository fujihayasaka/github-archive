# typed: true
# frozen_string_literal: true

class Businesses::PeopleController < Businesses::BusinessController
  before_action :read_enterprise_admins_and_members_required, only: %i(index)
  before_action :business_owner_required, except: %i(index)
  before_action :dotcom_required, except: %i(index)
  before_action :person_required, except: %i(index)
  before_action :business_not_downgraded_to_free_plan_required, except: %i(index)
  skip_before_action :cap_pagination, only: %i(index)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(index)

  def index
    query_args = parse_query_string(query_param,
      filter_map: BusinessesHelper::MEMBERS_QUERY_FILTERS,
    )

    members = this_business
      .filtered_members(
        current_user,
        query: query_args[:query],
        role: query_args[:role],
        account_type: query_args[:account_type]&.to_sym,
        deployment: query_args[:deployment],
        organization_logins: query_args[:organizations],
        license: query_args[:license],
        two_factor: query_args[:two_factor_status]&.to_sym,
        cost_center: query_args[:cost_center],
        order_by_direction: params[:sort_by].presence,
        batched_scope: this_business.feature_enabled?(:business_people_query_batching)
      )
      .paginate(page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/members_list", locals: {
            query: query_param,
            members: members,
            vss_enabled: this_business.volume_licensing_enabled?,
            connected_ghes_instances: this_business.enterprise_installations.any?,
          }
        else
          render "businesses/people", locals: {
            query: query_param,
            members: members,
          }
        end
      end
    end
  end

  # This removes the business user from the business and all orgs.
  def destroy
    return render_404 unless this_business.user_removal_available?

    if this_business.user_connected_to_enterprise?(person)
      if this_business.last_owner?(person)
        flash[:error] = "You can't remove the last owner of this enterprise account."
      elsif current_user == person && this_business.solitarily_owned_member_organizations(current_user).any?
        orgs_part = this_business.solitarily_owned_member_organizations(current_user).map(&:display_login).join(", ")
        flash[:error] = "You can't remove yourself from this enterprise account because you are the only owner of these organizations: #{orgs_part}."
      else
        RemoveBusinessMemberJob.perform_later(this_business.id, current_user.id, person.id)
        flash[:notice] = "Member queued for removal. This may take a few minutes to complete."
      end

      redirect_back(fallback_location: people_enterprise_path(this_business))
    else
      flash[:notice] = "User #{person.display_login} is not connected to the #{this_business.slug} enterprise."
      redirect_back(fallback_location: people_enterprise_path(this_business))
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_business
  end
end
