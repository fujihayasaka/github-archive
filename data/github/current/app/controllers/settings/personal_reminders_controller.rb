# typed: true
# frozen_string_literal: true

module Settings
  class PersonalRemindersController < ApplicationController

    before_action :login_required
    before_action { @selected_link = :reminders }
    javascript_bundle :reminders

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show, :index],
      optional: true

    def index
      if Apps::Privileged.integration(:slack).nil? && Apps::Privileged.integration(:msteams).nil?
        help_url = "https://github.com/integrations/slack/blob/master/README.md"
        flash[:error] = "Neither Slack nor Microsoft Teams App is configured. Learn more to configure at #{help_url}"
        redirect_to :back
        return
      end

      reminders = Reminders::PersonalReminderViewModel.all_by_type_for(current_user, cap_view_filter)
      respond_to do |format|
        format.html do
          render "settings/user/reminders/index", locals: {
            configured_reminders: reminders[:configured],
            available_reminders: reminders[:available],
            unavailable_reminders: reminders[:unavailable],
          }
        end
      end
    end

    def show
      personal_reminder = PersonalReminder.find_by(user: current_user, remindable: this_organization)
      personal_reminder ||= PersonalReminder.new(user: current_user, remindable: this_organization)

      render_edit(personal_reminder)
    end

    def update
      retries = 0
      personal_reminder = begin
        PersonalReminder.find_by(user: current_user, remindable: this_organization) || PersonalReminder.create(user: current_user, remindable: this_organization)
      rescue ActiveRecord::RecordNotUnique
        retry if (retries += 1) < 5

        flash[:error] = "There was an internal error trying to create your reminder. Please try again in a few moments."
        render_edit(PersonalReminder.new(user: current_user, remindable: this_organization))
        return
      end

      team_validation_errors = validate_team_options_from_params
      if team_validation_errors.any?
        flash[:error] = "There was an error: #{team_validation_errors.to_sentence}"
        render_edit(personal_reminder)
        return
      end

      if personal_reminder.update(personal_reminder_params)
        flash[:notice] = "Your reminder was updated successfully"
        redirect_to personal_reminders_path
      else
        flash[:error] = "There was an error: #{personal_reminder.errors.full_messages.to_sentence}"

        render_edit(personal_reminder)
      end
    end

    def reminder_test # rubocop:todo GitHub/UseRestfulActions
      personal_reminder = PersonalReminder.find_by!(user: current_user, remindable: this_organization)

      pull_requests = ActiveRecord::Base.connected_to(role: :reading) do
        personal_reminder.filtered_pull_requests
      end

      if pull_requests.empty?
        flash[:warn] = "We tried to send a test message, however you won't receive any messages because no matching pull requests were found."
      else
        ProcessReminderJob.perform_later(personal_reminder, delivery_target: Time.zone.now, test: true)
        flash[:notice] = "A test message is being sent."
      end

      redirect_to personal_reminders_path
    end

    def destroy
      personal_reminder = PersonalReminder.find_by!(user: current_user, remindable: this_organization)

      if personal_reminder.destroy
        flash[:notice] = "Your reminder was removed successfully"
      else
        flash[:error] = "An error occurred"
      end

      redirect_to personal_reminders_path
    end

    private

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      return :no_target_for_conditional_access if action_name == "index" # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_organization
    end

    def this_organization
      return if action_name == "index"
      @this_organization ||= current_user.organizations.find_by!(login: params[:organization_id])
    end
    helper_method :this_organization

    def render_edit(personal_reminder)
      respond_to do |format|
        format.html do
          view = create_view_model(
            Settings::PersonalReminders::EditView,
            personal_reminder: personal_reminder,
            available_chat_clients: available_chat_clients,
            client_param: params[:client],
          )
          render "settings/user/reminders/edit", locals: { view: view }
        end
      end
    end

    def available_chat_clients
      if ms_teams_feature_flag
        @chat_clients = [ReminderSlackWorkspace, ReminderTeamsWorkspace]
      else
        @chat_client = [ReminderSlackWorkspace]
      end
    end

    def ms_teams_feature_flag
      FeatureFlag.vexi.enabled?(:scheduled_reminders_ms_teams, this_organization, default: false)
    end
    helper_method :ms_teams_feature_flag

    sig { returns(T::Boolean) }
    def team_validation_feature_flag
      FeatureFlag.vexi.enabled?(:team_review_request_team_filtering, current_user, default: false)
    end
    helper_method :team_validation_feature_flag

    def ms_teams_client
      client_workspace_memberships = ReminderSlackWorkspaceMembership.where(user: current_user)
      client_workspace_ids = client_workspace_memberships.pluck(:reminder_slack_workspace_id)
      @ms_teams_workspace ||= ReminderTeamsWorkspace.find_by(remindable: this_organization, id: client_workspace_ids, teams_id: ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID)
    end

    def ms_teams_configured
      !ms_teams_client.nil?
    end
    helper_method :ms_teams_configured

    def personal_reminder_params

      personal_reminder_params = params.require(:personal_reminder).permit(
        :chat_client,
        :reminder_slack_workspace_id,
        :include_review_requests,
        :include_team_review_requests,
        :time_zone_name,
        :subscribed_to_events,
        {
          event_types: [], # for backwards compatibility
        },
        {
          reminder_event_subscriptions: [
            :event_type,
            :options,
          ],
        },
        {
          delivery_time: [
            { days: [] },
            { times: [] },
          ],
        },
      )

      # For the case when user is trying to configure reminders for Microsoft Teams client we need to remove any old slack id param that might be present
      # and replace that value with ms teams id that the user has membership to and is authorized for the organization
      if personal_reminder_params.delete(:chat_client) == ReminderTeamsWorkspace.name && ms_teams_feature_flag
        personal_reminder_params.delete(:reminder_event_subscriptions)
        personal_reminder_params.delete(:reminder_slack_workspace_id)
        teams_personal_workspace = ms_teams_client
        unless teams_personal_workspace.nil?
          personal_reminder_params[:reminder_slack_workspace_id] = teams_personal_workspace.id
        end
      end

      personal_reminder_params[:reminder_event_subscriptions] = [] unless personal_reminder_params.delete(:subscribed_to_events) == "1"

      if personal_reminder_params.delete(:subscribed_to_events) == "0"
        personal_reminder_params[:event_subscriptions_attributes] = []
      elsif personal_reminder_params[:reminder_event_subscriptions]
        event_subscriptions = personal_reminder_params[:reminder_event_subscriptions]
          .reject { |event| event[:event_type].to_s.blank? }
          .uniq { |event| event[:event_type].to_s }

        personal_reminder_params[:event_subscriptions_attributes] = event_subscriptions.map do |event_subscription|
          # Omit team options if feature flag is disabled
          if !team_validation_feature_flag && event_subscription[:event_type] == "team_review_request"
            { event_type: event_subscription[:event_type] }
          else
            { event_type: event_subscription[:event_type], options: event_subscription[:options].to_s }
          end
        end
      elsif personal_reminder_params[:event_types] # nb: temporary backwards compatibility for form
        event_types = personal_reminder_params[:event_types].reject(&:blank?).uniq
        personal_reminder_params[:event_subscriptions_attributes] = event_types.map do |type|
          { event_type: type }
        end
      end

      personal_reminder_params.delete(:event_types)
      personal_reminder_params.delete(:reminder_event_subscriptions)
      personal_reminder_params[:event_subscriptions_attributes].map(&:permit!) if personal_reminder_params[:event_subscriptions_attributes]

      personal_reminder_params[:delivery_times_attributes] = build_delivery_times_attributes(personal_reminder_params.delete(:delivery_time))
      personal_reminder_params[:delivery_times_attributes].map(&:permit!)
      personal_reminder_params
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

    # Validate team options for team_review_request event type
    sig { params(options_string: String).returns(T::Array[String]) }
    def validate_team_options(options_string)
      errors = []
      teams_limit = 5

      # Check string length (max [no. of teams * char limit for business team names] characters)
      char_limit = teams_limit * 100
      if options_string.length > char_limit
        errors << "Team list is too long (maximum #{char_limit} characters)"
      end

      # Check team count
      team_slugs = options_string.split(",").map(&:strip).reject(&:blank?)
      if team_slugs.length > teams_limit
        errors << "Too many teams selected (maximum #{teams_limit} teams)"
      end

      # Bail early if there are errors. No need to query for team membership if basic validation fails.
      return errors if errors.any?

      # Validate each team exists and user is a member
      visible_teams_by_slug = this_organization.visible_teams_for(current_user).where(slug: team_slugs).index_by(&:slug)
      team_slugs.each do |slug|
        team = visible_teams_by_slug[slug]
        if team.nil?
          errors << "Team '#{slug}' not found"
        elsif !team.member?(current_user)
          errors << "You are not a member of team '#{slug}'"
        end
      end

      errors
    end

    # Validate team options from form params
    sig { returns(T::Array[String]) }
    def validate_team_options_from_params
      return [] unless team_validation_feature_flag
      return [] unless params[:personal_reminder] && params[:personal_reminder][:reminder_event_subscriptions]

      all_errors = []

      params[:personal_reminder][:reminder_event_subscriptions].each do |event_subscription|
        # Ensure hash-like
        next unless event_subscription.respond_to?(:key?)
        next unless event_subscription.respond_to?(:[])

        event_type = event_subscription[:event_type]
        next unless event_type == "team_review_request"

        options = event_subscription[:options]
        next unless options.present?

        errors = validate_team_options(options.to_s)
        all_errors.concat(errors)
      end

      all_errors
    end
  end
end
