# typed: true
# frozen_string_literal: true

class Orgs::Settings::BlockedUsersController < Orgs::Controller

  before_action :login_required
  before_action :ensure_can_manage_blocked_users
  before_action :ensure_user_abuse_mitigation_enabled
  before_action :ensure_target_user, only: [:create, :destroy, :update]

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    render "settings/blocked_users/index"
  end

  def create
    # TODO: Eventually update `User#block` to use this PORO, instead of calling
    # it here. We call it here for now so we can ship it behind a feature flag
    # and make sure everything works.
    if params[:from_discussions] == "true"
      GitHub.dogstats.increment("block_and_hide_comments_from_discussion_comment_modal", tags: ["hide_comments:#{params[:hide_comments] == "on"}"])
    end

    if deletable_discussion
      deletion_type = "none"

      case params[:delete_discussion]
      when "this_discussion"
        deletion_type = "this_discussion"
        DiscussionDeleter.new(deletable_discussion).delete(current_user)
      when "all_in_org"
        deletion_type = "all_in_org"
        # Delete this discussion sychronously and then queue a job to delete all others
        DiscussionDeleter.new(deletable_discussion).delete(current_user)

        DiscussionDeleter.delete_all_in_org(
          owner: deletable_discussion&.repository&.owner, user: deletable_discussion&.user, actor: current_user
        )
      end

      # We want to track how often users are selecting the "delete this discussion" option to measure efficacy
      analytics_event(
        category: "BlockedUsersControllerCreate",
        action: "delete_discussion_while_blocking_user",
        label: "delete_discussion:#{deletion_type}"
      )

      GitHub.dogstats.increment("delete_discussion_while_blocking_user", tags: ["delete_discussion:#{deletion_type}"])
    end

    result = IgnoredUser::Creator.call(
      blocker: this_organization,
      blockee: target_user,
      actor: current_user,
      duration: params[:duration],
      blocked_from_content: content_for_notification,
      send_notification: params[:send_notification] == "on",
      minimize_comments: params[:hide_comments] == "on",
      minimize_reason: params[:hidden_reason],
      note: params[:note],
    )

    if request.xhr?
      return head :unprocessable_entity unless result.success?

      render partial: "settings/blocked_users/user", locals: {
        user_ignore: result.block,
      }
    else
      if result.success?
        flash[:notice] = result.message
      else
        flash[:error] = "An error occurred when trying to block the user: #{result.errors.to_sentence}"
      end

      safe_redirect_to(
        blockable_content&.permalink,
        fallback: organization_settings_blocked_users_path(this_organization),
      )
    end
  end

  def destroy
    this_organization.unblock(target_user, actor: current_user)
    flash[:notice] = "User has been successfully unblocked from this organization."

    safe_redirect_to(
      blockable_content&.permalink,
      fallback: organization_settings_blocked_users_path(this_organization),
    )
  end

  def update
    ignored_user_record = this_organization.ignored_users.find_by(ignored: target_user)

    if ignored_user_record.present?
      updated_note = params[:clear] == "true" ? nil : params[:note]

      if ignored_user_record.update(note: updated_note)
        flash[:notice] = [
          "The note was successfully",
          params[:clear] == "true" ? "cleared." : "updated.",
        ].join(" ")
      else
        flash[:error] = [
          "There was a problem saving the note:",
          ignored_user_record.errors.full_messages.to_sentence,
        ].join(" ")
      end
    else
      flash[:error] = "The user is not currently blocked from this organization."
    end

    redirect_to organization_settings_blocked_users_path(this_organization)
  end

  private

  def ensure_user_abuse_mitigation_enabled
    render_404 unless GitHub.user_abuse_mitigation_enabled?
  end

  def ensure_can_manage_blocked_users
    render_404 unless this_organization.blocked_users_manageable_by?(current_user)
  end

  # Private: Find the target user to be blocked / unblocked
  #
  # Returns a User|nil.
  memoize def target_user
    User.find_by(login: params[:login])
  end

  def ensure_target_user
    render_404 unless target_user.present?
  end

  # If we're blocking a discussion or a discussion comment, and if the user has permission to do so
  sig { returns(T.nilable(Discussion)) }
  memoize def deletable_discussion
    return nil unless blockable_content.is_a?(Discussion)
    return nil unless blockable_content.repository.owner == this_organization

    if blockable_content.is_a?(Discussion)
      blockable_content
    else
      blockable_content.discussion
    end
  end

  # Private: Loads the blockable content, if we are blocking a user
  #          from a piece of content.
  #
  # Returns an OrgBlockable|nil.
  def blockable_content # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @blockable_content if defined?(@blockable_content)
    return @blockable_content = nil unless params[:content_id].present?

    @blockable_content = begin
      typed_object_from_id([Platform::Interfaces::OrgBlockable], params[:content_id])
    rescue Platform::Errors::NotFound
      nil
    end
  end

  def content_for_notification
    return nil if blockable_content.nil? || blockable_content.destroyed?
    blockable_content
  end
end
