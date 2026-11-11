# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamMembersController < Stafftools::Businesses::BusinessBaseController
  include ApplicationController::VerifiedFetchDependency
  include BusinessesHelper

  skip_before_action :dotcom_required
  allow_verified_fetch only: %i(destroy)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  PER_PAGE = 30 # Rails default

  sig { void }
  def index
    if using_business_teams?
      business_team_members_index
    else
      enterprise_team_members_index
    end
  end

  sig { void }
  def destroy
    business_team = this_business.business_teams.find_by(id: params[:enterprise_team_id])
    return render_404 if business_team.nil?
    member = business_team.members.find_by(id: params[:id])
    return render_404 if member.nil?

    if business_team.externally_managed?
      return render(
        json: {
          data: {
            error: "Members cannot be removed from the externally managed #{business_team.name} enterprise team."
          }
        }, status: :bad_request
      )
    end

    business_team.remove_member(member, caller_type: :business_team)

    render(json: {
      data: {
        message: "#{member} is being removed from the #{business_team.name} enterprise team.",
        redirect: stafftools_enterprise_team_members_path(this_business, business_team),
      }
    }, status: :ok)
  end

  private

  sig { void }
  def enterprise_team_members_index
    enterprise_team = this_business.enterprise_teams.find_by(id: params[:enterprise_team_id])
    return render_404 if enterprise_team.nil?

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    memberships = []
    if enterprise_team.direct_memberships_enabled?
      # No active record associations from User -> EnterpriseTeamMembership, have to start from ETM
      memberships = enterprise_team.enterprise_team_memberships
        .includes(:user)
        .where("users.login LIKE ?", "%#{query}%")
        .order("users.login")
        .paginate(page: current_page, per_page: PER_PAGE)
    end

    render "stafftools/businesses/enterprise_teams/direct_members", locals: {
      this_business: this_business,
      enterprise_team: enterprise_team,
      memberships: memberships,
    }
  end

  sig { void }
  def business_team_members_index
    business_team = this_business.business_teams.find_by(id: params[:enterprise_team_id])
    return render_404 if business_team.nil?

    query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
    members = business_team.members
      .where("login LIKE ?", "%#{query}%")
      .order(:login)
      .paginate(page: current_page, per_page: PER_PAGE)

    payload = {
      totalEntries: members.total_entries,
      totalPages: members.total_pages,
      businessSlug: this_business.slug,
      enterpriseTeam: {
        id: business_team.id,
        name: business_team.name,
        slug: business_team.slug,
        memberCount: business_team.members.count,
        showRoute: stafftools_enterprise_team_path(this_business, business_team.id),
        canMembersBeRemoved: !business_team.externally_managed?,
      },
      members: members.map do |member|
        {
          id: member.id,
          login: member.display_login,
          name: member.name,
          showRoute: stafftools_user_path(member),
        }
      end
    }

    T.unsafe(self).class.react_bundle_name = "business-teams"

    respond_to do |format|
      format.json do
        render json: payload
      end
      format.html do
        render_react_app(
          payload: payload,
          layout: "layouts/stafftools/business",
          title: business_team.name,
        )
      end
    end
  end

  sig { returns(T::Boolean) }
  private def using_business_teams?
    !!(!this_business.enterprise_teams_enabled? && BusinessTeam.enabled_for_enterprise?(business: this_business))
  end

  sig { params(page_param: Symbol).returns(Integer) }
  private def current_page(page_param = :page)
    if params[page_param].blank? || !params[page_param].respond_to?(:to_i)
      1
    else
      params[page_param].to_i.abs
    end
  end
end
