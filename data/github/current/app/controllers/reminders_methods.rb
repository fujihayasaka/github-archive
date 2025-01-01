# typed: true
# frozen_string_literal: true

# Usage:
#
# This concern allows for significant re-use of code between various parts of GitHub (orgs, teams, etc)
# Some high-level documentation is provided here, while each method has comments inline as well
#
# Some methods *must* be overridden and others provide an _optional_ override:
# - index [required, public]
#   * implements the view logic and renders a template for the index action
# - reset [required, public]
#   * implements reset logic for the given scope, deleting all reminders and possible other relations
# - render_edit [required, private]
#   * called from various routes like new and show. Renders a form for a specific reminder that is passed as a parameter
# - scope_reminders [optional, private]
#   * By default it will not scope anything. When overridden, it will allow you to scope your calls to specific reminders based on attributes like team memberships
#
module RemindersMethods
  extend T::Helpers
  extend ActiveSupport::Concern
  include PlatformHelper
  include Orgs::RemindersHelper

  requires_ancestor { Orgs::Controller }

  included do
    T.bind(self, T.class_of(::Orgs::Controller))

    before_action :login_required
    helper_method :reminders_url_for
    javascript_bundle :reminders
  end

  # This is a helper method in the controller and views that allow a polymorphic url in the scope of the current controller
  def reminders_url_for(action, params = {})
    url_params = {
      controller: controller_name,
      action: action,
    }
    url_params.merge!(params)
    url_for(**url_params)
  end

  def self.reminders_enabled?(organization)
    if GitHub.multi_tenant_enterprise?
      return organization.feature_enabled?(:enable_scheduled_reminders)
    end
    true
  end

  # This must be implemented on all subclasses. You likely want:
  # respond_to do |format|
  #   format.html do
  #     view = create_view_model(
  #       Reminders::IndexView,
  #       slack_workspaces: slack_workspaces,
  #       organization: this_organization,
  #       locked_to_team: this_team, (optional)
  #       ... additional params ...
  #     )
  #     render "<CUSTOM PATH>/reminders/index", locals: { view: view }
  #   end
  # end
  def index
    raise NotImplementedError, "Must implement index route action"
  end

  def new
    preselected_slack_workspace = slack_workspaces.find_by(id: params[:workspace_id])
    reminder = Reminder.new(remindable: this_organization, slack_workspace: preselected_slack_workspace, user: current_user)
    reminder = scope_reminders(reminder)

    render_edit(reminder)
  end

  def show
    render_edit(@reminder)
  end

  def create
    build_reminder = ->() do
      reminder = Reminder.new(remindable: this_organization, user: current_user)
      reminder = scope_reminders(reminder)
      reminder.assign_attributes(reminder_params)
      reminder
    end

    reminder = build_reminder.call
    unless reminder.save
      flash[:error] = "There was an error: #{reminder.errors.full_messages.to_sentence}"
      render_edit(reminder)
      return
    end

    # To be able to redirect to a reminder in the resulting message, we first need an ID.
    # Since we were able to save above, we know that we have a valid object now and can form that URL.
    # However, we still need to post the message. If the message succeeds, then we can continue.
    # If it fails, we will delete the reminder we had above so we can create a stub with the errors.
    if reminder.valid? && reminder.slack_workspace.validate_and_post_message(current_user, reminders_url_for(:show, id: reminder.id), reminder)
      if reminder.slack_channel_id
        reminder.save! # Saves the channel ID
        flash[:notice] = "Okay, the reminder has been created."
      else
        # channel creation is pending
        flash[:notice] = "Okay, we're creating a reminder for the channel right now. It may take several seconds."
      end
    else
      errors = reminder.errors[:slack_channel]
      reminder.destroy!

      reminder = build_reminder.call
      errors.each { |err| reminder.errors.add(:slack_channel, err) }

      render_edit(reminder)
      return
    end

    redirect_to reminders_url_for(:index)
  end

  def reminder_test
    results = ActiveRecord::Base.connected_to(role: :reading) do
      @reminder.filtered_pull_requests
    end

    if results.empty?
      flash[:warn] = "We tried to send a test message, however you won't receive a a message because no matching pull requests were found."
    else
      ProcessReminderJob.perform_later(@reminder, delivery_target: Time.zone.now, test: true)
      flash[:notice] = "A test message is being sent to ##{@reminder.display_name}."
    end

    redirect_to reminders_url_for(:index)
  end

  def update
    # We want this next block in a DB transaction as we manipulate the associated has_many collections when we call `assign_attributes`. When we do this, those objects
    # are automatically deleted (like `team_memberships`). In the case that validation fails after/during the assignment, we need to make sure those deletes are rolled back. To accomplish this, a DB txn
    # is used. If we are not valid (has errors), then we raise `ActiveRecord::Rollback` to cause the deleted records to be rolled back.
    @reminder.transaction do
      @reminder.assign_attributes(reminder_params)
      unless @reminder.valid?
        flash[:error] = "There was an error: #{@reminder.errors.full_messages.to_sentence}"
        raise ActiveRecord::Rollback
      end
    end

    # Now, if we are valid (no errors) then we want to tell the channel that we are updating the reminder. The method checks for validity with a guard.
    # However, it is possible that the slack channel could be incorrect/invalid. This will add errors to the reminder object if needed.
    reminder_url = reminders_url_for(:show, id: @reminder.id)
    if @reminder.valid? # Don't want to send a message unless the reminder is valid
      @reminder.slack_workspace.validate_and_post_message(current_user, reminder_url, @reminder)
    end
    # Finally, if we are still valid (no errors) and can save, then redirect, otherwise render the edit page.
    if @reminder.errors.empty? && @reminder.save
      flash[:notice] = "Okay, the reminder has been updated."
      redirect_to reminders_url_for(:index)
    else
      render_edit(@reminder)
    end
  end

  def destroy
    if @reminder.destroy
      flash[:notice] = "Reminder removed"
    else
      flash[:error] = "There was an error: #{@reminder.errors.full_messages.to_sentence}"
    end

    redirect_to reminders_url_for(:index)
  end

  def team_autocomplete
    scope = this_organization.visible_teams_for(current_user).closed.limit(25)
    teams = Team.search_name_and_slug(query: params[:q], scope: scope).to_a

    respond_to do |format|
      format.html_fragment do
        render partial: "reminders/form/team_autocomplete", formats: :html, locals: {
          query: params[:q],
          teams: teams,
        }
      end
    end
  end

  def repository_suggestions
    set_reminder if params[:id]

    # This codepath can be used by organization reminders and team reminders
    # In the case of team reminders, we want to use `this_team` to scope
    # In the case of organization, we will only scope if the reminder has teams set
    teams = if defined?(this_team) && this_team
      [this_team]
    elsif @reminder && @reminder.team_memberships.present?
      @reminder.teams.to_a.compact
    else
      nil
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "reminders/form/repository_suggestions", formats: :html, locals: {
          view: create_view_model(Reminders::RepositorySuggestionsView,
            organization: this_organization,
            query: params[:q],
            teams: teams
          )
        }
      end
    end
  end

  private

  # Overriding this method lets you scope methods based on the current controller
  # For example, if you are on a teams settings page you only want to see/change reminders that are a part of that team
  # This method should be able to accept:
  # - Hash & ActionController::Parameters
  # - ActiveRecord::Relation
  # - Reminder instance
  def scope_reminders(reminder)
    reminder
  end

  # Overriding this method allows the edit view to be customized.
  # By overriding the edit view, you can set specific instance variables like team to indicate if the view is for a specific team or many.
  # You likely want:
  # respond_to do |format|
  #   format.html do
  #     view = create_view_model(
  #       Reminders::EditView,
  #       slack_workspaces: slack_workspaces,
  #       reminder: reminder,
  #       locked_to_team: this_team, (optional)
  #       ... additional params ...
  #     )
  #     render "<CUSTOM PATH>/reminders/edit", locals: { view: view }
  #   end
  # end
  def render_edit(reminder)
    raise NotImplementedError, "Must implement render_edit"
  end

  def set_reminder!
    set_reminder
    render_404 if @reminder.nil?
  end

  def set_reminder
    @reminder = scope_reminders(Reminder.for_remindable(this_organization).find(params[:id]))
  end

  def slack_workspaces
    ## Feature flag based on which it will either call ReminderClientWorkspace or ReminderSlackWorkspace
    ## Basically till all code is complete with all possible scenarios we will use this flag to ensure it is turned off for all users
    if this_organization.feature_enabled?(:scheduled_reminders_ms_teams_for_org)
      @slack_workspaces ||= ReminderClientWorkspace.includes(:reminders).for_remindable(this_organization)
    else
      @slack_workspaces ||= ReminderSlackWorkspace.includes(:reminders).for_remindable(this_organization)
    end
  end

  def reminder_params
    reminder_params = params.require(:reminder).permit(
      :reminder_slack_workspace_id,
      :repositories_target,
      :slack_channel,
      { tracked_repository_ids: [] },
      :ignore_draft_prs,
      :require_review_request,
      :ignore_after_approval_count,
      :ignored_terms,
      :ignored_labels,
      :required_labels,
      :min_age,
      :min_staleness,
      :include_reviewed_prs,
      :needed_reviews,
      :time_zone_name,
      { team_ids: [] },
      {
        delivery_time: [
          { days: [] },
          { times: [] },
        ],
      }
    )

    if reminder_params.delete(:repositories_target) == "all"
      reminder_params[:tracked_repository_ids] = []
    elsif repo_ids = reminder_params.delete(:tracked_repository_ids)
      reminder_params[:tracked_repository_ids] = repo_ids
      # else not set (nil)
    end

    reminder_params[:delivery_times_attributes] = build_delivery_times_attributes(reminder_params.delete(:delivery_time))
    reminder_params[:delivery_times_attributes].map(&:permit!)
    reminder_params[:user_id] = current_user.id
    scope_reminders(reminder_params)
  end

  # Combine user-supplied day, time, and time zone into delivery time attributes
  def build_delivery_times_attributes(delivery_time_params)
    delivery_time_params ||= {}

    times = Array(delivery_time_params[:times]).uniq.select(&:present?)
    days = Array(delivery_time_params[:days]).uniq.select(&:present?)

    days.product(times).map do |(day, time)|
      { day: day, time: time }
    end
  end
end
