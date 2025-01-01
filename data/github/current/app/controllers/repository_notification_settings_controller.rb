# typed: true
# frozen_string_literal: true

class RepositoryNotificationSettingsController < AbstractRepositoryController
  include GitHub::RateLimitedRequest


  before_action :ensure_admin_access
  before_action :sudo_filter, except: [:index]

  layout "repository"
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index, :edit]

  # This configures rate limiting for the :update action
  # At present there is no verification of the email addresses users
  # can configure, which creates a vector for spam and abuse, as
  # discussed in https://github.com/github/platform-health-incidents/issues/217
  # These rate limits are aggressive: only a few successful updates in 24 hours
  # are allowed.
  # To improve UX a little, we only check the rate limit here, without incrementing
  # and only increment after a successful update.
  UPDATE_RATE_LIMIT_TTL = 24.hours
  UPDATE_RATE_LIMIT_MAX = 3
  rate_limit_requests \
    only: :update,
    key: :update_rate_limit_key,
    max: UPDATE_RATE_LIMIT_MAX,
    ttl: UPDATE_RATE_LIMIT_TTL,
    at_limit: :at_rate_limit,
    stealthy: true

  def index
    # immediately render the "edit" form if there is no hook setup yet
    return redirect_to(action: :edit) if current_hook.new_record?

    render "edit_repositories/pages/notifications", locals: { repository: current_repository, hook: current_hook }
  end

  def edit
    render "edit_repositories/pages/edit_notifications", locals: { repository: current_repository, hook: current_hook }
  end

  def update
    if current_hook.update(hook_params)
      flash[:notice] = "Repository notification settings updated."

      # We explicitly update the rate limit only after a successful update
      # to avoid users getting blocked by entering invalid emails and wanting
      # to fix it
      rate_limit_increment(rate_limit_key, { ttl: UPDATE_RATE_LIMIT_TTL })
      redirect_to action: :index
    else
      flash.now[:error] = current_hook.errors.full_messages.to_sentence
      edit
    end
  end

  def destroy
    return redirect_to :back if current_hook.new_record?

    if current_hook.destroy
      flash[:notice] = "Repository notification settings cleared."
      redirect_to action: :index
    else
      flash[:notice] = "There was a problem deleting your repository notification settings."
      redirect_to :back
    end
  end

  def at_rate_limit # rubocop:todo GitHub/UseRestfulActions
    flash.now[:error] = "You've updated this setting too many times today, please try again tomorrow."
    edit
  end

  private

  def current_context
    current_repository
  end

  # find or initialize the Hook model for notification settings with default values
  #
  # Returns an instance of Hook configured for "email"
  memoize def current_hook
    if current_repository.repo_hook_associations_ff?
      hook = Hook.email_hooks_for_target(current_repository).first
      hook ||= begin
        Hook.new(
          installation_target: current_repository,
          name: "email",
          active: true,
          events: ["push"],
          creator: current_user
        )
      end
    else
      (
        current_repository.email_hooks.first ||
        current_repository.email_hooks.new(active: true, events: ["push"], creator: current_user)
      )
    end
  end

  # allowable hook, and (nested hook_config) parameters
  # Note: the view should include a hidden_field_tag for `hook[active]` set to `"0"`
  #       to ensure that a value is passed when unchecked
  def hook_params
    params.require(:hook).permit(
      :active,
      { config_attributes: [:address, :secret, :send_from_author] },
    )
  end

  def update_rate_limit_key
    "#{self.class.to_s.underscore}.update_check:#{current_repository.id}"
  end
end
