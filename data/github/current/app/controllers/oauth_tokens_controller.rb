# typed: true
# frozen_string_literal: true

class OauthTokensController < ApplicationController
  include Organization::CredentialAuthorizationsHelper

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required
  before_action :check_eligibility, only: [:new, :create]
  before_action :sudo_filter, except: [:destroy, :index, :remove_authorization]
  before_action :set_cache_control_no_store, only: [:index]

  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :show],
    optional: true

  # When the user selects all scopes and we normalize it down to 3, we want to tell them why
  NORMALIZED_MESSAGE = "Some of the scopes you’ve selected are included in" \
    " other scopes. Only the minimum set of necessary scopes has been saved."

  # It is preferable to synchronously revoke all personal access tokens at once,
  # so that the tokens will already be gone when the user is redirected back to
  # their personal access tokens page. But, if the user has a large number of
  # tokens, we need to do it asynchronously in a job.
  MAXIMUM_TOKENS_REVOKE_ALL = 100

  PER_PAGE = 10

  BETA_VERSION = "beta"

  helper_method :show_sso_ready_badge?

  def index
    context_region_preset :developer_settings

    # Temporary join used to filter out bad data in the DB where an access has no authorization.
    # Eventually this join can be removed when the bad data in the DB is cleaned up.
    # https://github.com/github/github/issues/117741
    if current_user.patsv2_enabled? && params[:type] == BETA_VERSION
      tokens = ProgrammaticAccess.for(current_user)
        .order(created_at: :desc)
        .paginate(page: current_page, per_page: PER_PAGE)
      render "personal_access_tokens/index", locals: { tokens: tokens }
    else
      personal_tokens = current_user
        .oauth_accesses.personal_tokens
        .joins(:authorization).order(created_at: :desc)
        .paginate(page: current_page, per_page: PER_PAGE)

      render "oauth_tokens/index", locals: { tokens: personal_tokens }
    end
  end

  def new
    scopes = params[:scopes].to_s.split(",")
    @access = current_user.oauth_accesses.build(description: params[:description], scopes: scopes)
    @access.default_expires_at = params[:default_expires_at] if params[:default_expires_at]

    render "oauth_tokens/new"
  end

  def create
    hash = params[:oauth_access]
    normalized_scopes = normalize_scopes_from(hash[:scopes])
    @access = current_user.oauth_accesses.build do |access|
      access.application_id = OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
      access.application_type = OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
      access.description = hash[:description]
      access.scopes = normalized_scopes
    end

    @access.set_expiration(hash[:default_expires_at], hash[:custom_expires_at])
    return render "oauth_tokens/new" if @access.errors.any?

    token = @access.set_random_token_pair

    if scopes_normalized?(hash[:scopes], normalized_scopes)
      flash[:notice] = NORMALIZED_MESSAGE
    end

    # Build instance before saving it so we track the GTID properly
    # of the save operation.
    last_operations = DatabaseSelector::LastOperations.from_token(token)

    if @access.save
      # After saving the new token we want to set the last write gtids/timestamps in the cache,
      # so the api DatabaseSelection can use the write DB for newly created tokens and avoid issues
      # due to replication lag.
      last_operations.store_latest_writes

      flash[:new_personal_access] = { id: @access.id, token: token }
      redirect_to settings_user_tokens_path
    else
      render "oauth_tokens/new"
    end
  end

  def show
    @access = current_user.oauth_accesses.personal_tokens.find_by(id: params[:id])
    return(render_404) unless @access

    @access.default_expires_at = @access.expires_at ? "custom" : "none"
    @access.custom_expires_at = @access.expires_at

    render "oauth_tokens/show"
  end

  def update
    @access = current_user.oauth_accesses.personal_tokens.find(params[:id])
    hash = params[:oauth_access]
    normalized_scopes = normalize_scopes_from(hash[:scopes])
    @access.description = hash[:description]
    @access.scopes = normalized_scopes
    # Older personal access tokens will have a code set that is not needed.
    @access.code = nil

    if scopes_normalized?(hash[:scopes], normalized_scopes)
      flash[:notice] = NORMALIZED_MESSAGE
    end

    if @access.save
      redirect_to settings_user_tokens_path
    else
      render "oauth_tokens/show"
    end
  end

  def regenerate_edit # rubocop:todo GitHub/UseRestfulActions
    @access = current_user.oauth_accesses.personal_tokens.find(params[:id])
    @index_page = params[:index_page]

    render "oauth_tokens/regenerate_edit"
  end

  def regenerate # rubocop:todo GitHub/UseRestfulActions
    @access = current_user.oauth_accesses.personal_tokens.find(params[:id])
    @access.code = nil

    @access.set_expiration(
      params.dig(:oauth_access, :default_expires_at),
      params.dig(:oauth_access, :custom_expires_at)
    )

    return render "oauth_tokens/regenerate_edit" if @access.errors.any?

    token, error = reset_token_with_expiry_for(@access)

    if token.present? && @access.valid?
      GitHub.dogstats.increment("oauth_tokens.regenerate", tags: ["result:success"])
      flash[:new_personal_access] = { id: @access.id, token: token }
    else
      flash[:error] =
        if error
          "Your token is invalid due to the following issues: #{error}. Please resolve these issues and try again."
        else
          "An error ocurred when regenerating this token, please try again"
        end
    end

    if !params[:index_page].blank?
      redirect_to settings_user_tokens_path(page: params[:index_page])
    else
      redirect_to settings_user_token_path(@access)
    end
  end

  def destroy
    access = current_user.oauth_accesses.personal_tokens.find(params[:id])
    access.destroy_with_explanation(:web_user, entry_point: :oauth_tokens_controller_destroy)

    if request.xhr?
      head 200
    else
      redirect_to settings_user_tokens_path
    end
  end

  def revoke_all # rubocop:todo GitHub/UseRestfulActions
    if current_user.oauth_accesses.personal_tokens.count > MAXIMUM_TOKENS_REVOKE_ALL
      current_user.async_revoke_oauth_tokens(:personal_tokens)
      flash[:notice] = "Revoking all personal access tokens"
    else
      current_user.revoke_oauth_tokens(:personal_tokens)
      flash[:notice] = "Revoked all personal access tokens"
    end
    redirect_to settings_user_tokens_path
  end

  def remove_authorization # rubocop:todo GitHub/UseRestfulActions
    token = current_user.oauth_accesses.personal_tokens.find(params[:id])
    org = Organization.find_by_login(params[:org])

    authorization = Organization::CredentialAuthorization.authorization \
      organization: org, credential: token
    return render_404 unless authorization

    authorization.destroy

    redirect_to settings_user_tokens_path,
      notice: "The token is no longer authorized to access #{ org.display_login }."
  end

  private

  def scopes_normalized?(original, normalized)
    !original.blank? && !normalized.blank? && (original.length > normalized.length)
  end

  def check_eligibility
    if current_user.must_verify_email?
      flash[:error] = "Creating a personal access token requires a verified email address."
      render_email_verification_required
    end
  end

  # Internal: Normalize the OAuth scopes such that redudant scopes are filtered
  # out. If a site administrator has requested the site_admin scope, allow it.
  #
  # scopes - The string based representation of requested scopes from params
  #
  # Returns an Array of String scopes.
  def normalize_scopes_from(scopes)
    normalized_scopes = OauthAccess.normalize_scopes(scopes)

    if scopes&.include?("site_admin") && current_user&.site_admin_scope_allowed?
      normalized_scopes << "site_admin"
    end

    # Ensure the correct order and remove any duplicate scopes.
    OauthAccess.normalize_scopes(normalized_scopes, visibility: :all)
  end

  # Internal: Safely resets an access token without raising exceptions when
  # validation errors are encountered on the note/description field.
  #
  # Context:
  #   - https://github.com/github/ecosystem-apps/issues/988
  #   - https://github.com/github/ecosystem-apps/issues/2469
  #
  # Returns a tuple [token, error].
  def reset_token_with_expiry_for(access)
    [access.reset_with_expiry(expires_at: access.expires_at), nil]
  rescue ActiveRecord::RecordInvalid => e
    raise e unless access.errors.details[:note].any? do |e|
      [:github_token_prefix, :taken].include?(e[:error])
    end

    message =
      if access.errors.any?
        access.errors.full_messages.to_sentence
      else
        e.message
      end

    [nil, message]
  end
end
