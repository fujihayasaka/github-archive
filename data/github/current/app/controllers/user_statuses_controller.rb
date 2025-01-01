# typed: true
# frozen_string_literal: true

class UserStatusesController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  skip_before_action :perform_conditional_access_checks, # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    only: [:update, :emoji_picker, :org_picker, :show]

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:member_statuses]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:emoji_picker]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:org_picker]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:member_statuses], optional: true

  class MemberStatusPage
    attr_reader :member_statuses, :start_cursor, :page_data

    def initialize(member_statuses:, page_size:, start_cursor:)
      @member_statuses = member_statuses
      @page_size = page_size
      @start_cursor = start_cursor
      @page_data = @member_statuses[start_cursor, page_size]
    end

    def has_previous_page?
      start_cursor.to_i > 0
    end

    def end_cursor
      start_cursor + page_data.size
    end

    def has_next_page?
      member_statuses[end_cursor + 1].present?
    end
  end

  STATUS_COUNT_FOR_LATER_PAGE = 15
  STATUS_COUNT_FOR_ORG_DASHBOARD = 6
  STATUS_COUNT_FOR_TEAM_PAGE = 3

  def member_statuses # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_organization
    return render_404 if this_team && !this_team.visible_to?(current_user)

    start_cursor = params[:after].to_i
    member_statusable = this_team || this_organization

    statuses = if member_statusable.is_a?(Organization) && !member_statusable.member_or_can_view_members?(current_user)
      []
    else
      member_statusable.member_statuses(viewer: current_user)
    end

    member_statuses = statuses[start_cursor, statuses_per_page]

    page = MemberStatusPage.new(member_statuses: statuses, page_size: statuses_per_page, start_cursor: start_cursor)

    respond_to do |format|
      format.html do
        render partial: "user_statuses/member_statuses",
          locals: {
            member_statusable: member_statusable,
            member_statuses: page.page_data,
            page_info: page
          }
      end
    end
  end

  def show
    respond_to do |format|
      format.html do
        render partial: "user_statuses/edit", locals: {
          truncate: params[:truncate] == "1",
          link_mentions: params[:link_mentions] == "1",
          compact: params[:compact] == "1",
          circle: params[:circle] == "1"
        }
      end
      format.html_fragment do
        render partial: "user_statuses/dialog", locals: {
          truncate: params[:truncate] == "1",
          link_mentions: params[:link_mentions] == "1",
          compact: params[:compact] == "1",
          circle: params[:circle] == "1",
        }, formats: :html
      end
    end
  end

  def update
    input = {
      message: params[:message].presence,
      emoji: params[:emoji].presence,
      expires_at: params[:expires_at].presence,
      limited_availability: params[:limited_availability] == "1",
    }

    status = begin
      if org_id = params[:organization_id].presence
        input[:org] = Organization.find(org_id)
      end
      UserStatus.set_for(current_user, **input)
      :ok
    rescue ActiveRecord::RecordNotFound
      :unprocessable_entity
    end

    current_user.reload_user_status # Ensure latest status is used

    respond_to do |format|
      format.html do
        if header_redesign_enabled? && params[:from_side_panel].present?
          render Site::Header::UserStatusItemComponent.new(user_status: current_user.user_status_when_not_expired), layout: false, status: status
        else
          render partial: "user_statuses/edit", locals: {
            truncate: params[:truncate] == "1",
            link_mentions: params[:link_mentions] == "1",
            compact: params[:compact] == "1",
            circle: params[:circle] == "1"
          }, status: status
        end
      end
      format.json do
        render "user_statuses/show"
      end
    end
  end

  def emoji_picker # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "user_statuses/emoji_picker",
               locals: { status: current_user.user_status_when_not_expired }
      end
    end
  end

  def org_picker # rubocop:todo GitHub/UseRestfulActions
    status = current_user.user_status_when_not_expired
    organizations = current_user.organizations.take(100).sort_by(&:display_login)

    respond_to do |format|
      format.html do
        render partial: "user_statuses/org_picker", locals: { viewer: current_user, status: status, organizations: organizations }
      end
    end
  end

  private

  def statuses_per_page
    if params[:after]
      STATUS_COUNT_FOR_LATER_PAGE
    elsif params[:org_dashboard] == "1"
      STATUS_COUNT_FOR_ORG_DASHBOARD
    else
      STATUS_COUNT_FOR_TEAM_PAGE
    end
  end

  memoize def this_organization
    if params[:org]
      Organization.find_by_login(params[:org])
    end
  end

  memoize def this_team
    if params[:team] && this_organization
      this_organization.teams.find_by_slug(params[:team])
    end
  end

  def target_for_conditional_access
    if params[:action] == "member_statuses"
      # When listing statuses, these are statuses set by members of an org that should
      # only be seen by other members of the org, so those statuses can be considered
      # the org's data
      this_organization || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    else
      # #update, #show endpoints are for setting the current user's status, and `this_organization`
      # is only used to restrict which org, if any, can see the user's status; the data
      # is owned by the current user, though
      current_user
    end
  end
end
