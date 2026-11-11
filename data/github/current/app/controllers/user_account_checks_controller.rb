# typed: strict
# frozen_string_literal: true

class UserAccountChecksController < ApplicationController
  set_statsd_sample_rate 0.01, only: [:username_check, :email_check]

  include Signups::SuggestedUsernamesDependency

  before_action :login_required, except: [:username_check, :email_check]

  # This controller does not access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    only: [:username_check]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "UserAccountChecksController#username_check",
  ]

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:username_check, :email_check],
    key: :signup_check_rate_limit_key,
    max: :signup_check_rate_limit_max,
    ttl: :signup_check_rate_limit_ttl,
    at_limit: :record_username_check_limit

  if enterprise?
    skip_before_action :first_run_check, only: %w( username_check email_check )
  end

  sig { returns(T.untyped) }
  def username_check # rubocop:todo GitHub/UseRestfulActions - https://github.com/github/new-user-experience/issues/1545
    username = params[:value]
    Failbot.push(user: username) # Since errors will occur before account creation this won't count as EUII

    # create a temporary user with the provided username so we can run model validations on it
    user = User.new(login: username, persistent_client_id: persistent_client_id)
    # mark it as readonly so that any changes in this check cannot be saved accidentally
    user.readonly!
    # trigger validations - we only care about the login validation here (not password, email, or anything else)
    user.valid?

    login_errors = user.errors[:login]
    suggest_usernames = true
    respond_to do |format|
      format.html_fragment do
        if !login_errors.empty?
          if suggest_usernames?(login_errors: login_errors, suggest_usernames_param: suggest_usernames)
            suggested_usernames = get_username_suggestions(base_username: user.display_login)
          end
          return render partial: "signup/invalid_username", formats: :html, status: 422, locals: {
            error_message:  user.login_error_message,
            suggested_usernames: suggested_usernames,
            source: params[:source],
          }
        end

        render html: "#{user.display_login} is available."
      end
    end
  end

  sig { returns(T.untyped) }
  def email_check # rubocop:todo GitHub/UseRestfulActions - https://github.com/github/new-user-experience/issues/1545
    respond_to do |format|
      format.html_fragment do
        user = User.new(email: params[:value])
        return head :ok unless !user.valid? && user.errors[:emails].any?

        sanctioned_email_errors = user.errors.where(:email, :sanctioned_email)
        disposable_email_errors = user.errors.where(:email, :disposable_email)

        if sanctioned_email_errors.any?
          email_error = ::TradeControls::Notices.sanctioned_domain_email_warning
        elsif disposable_email_errors.any?
          email_error = "Email #{UserEmail::VALIDATION_ERRORS[:generic_domain]}"
        else
          email_error = "Email is invalid or already taken"
        end

        render body: email_error, status: 422, content_type: "text/fragment+html"
      end
    end
  end

  private

  sig { returns(T.nilable(String)) }
  def signup_check_rate_limit_key
    case action_name
    when "username_check"
      "user_account_checks_controller.username_check:#{request.remote_ip}"
    when "email_check"
      "email-check:#{request.remote_ip}"
    end
  end

  sig { returns(T.untyped) }
  def signup_check_rate_limit_max
    case action_name
    when "username_check"
      100
    when "email_check"
      GitHub.email_check_rate_limit
    end
  end

  sig { returns(T.untyped) }
  def signup_check_rate_limit_ttl
    case action_name
    when "username_check"
      GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL
    when "email_check"
      GitHub.email_check_ttl
    end
  end

  sig { returns(T.untyped) }
  def record_username_check_limit
    GitHub.dogstats.increment("rate_limited", tags: ["action:username_check"]) if action_name == "username_check"
  end
end
