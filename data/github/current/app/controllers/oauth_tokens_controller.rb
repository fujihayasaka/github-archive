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

  FAILURE_MESSAGE = "An error occurred when creating this token, please try again."

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

    if current_user.patsv2_enabled? && params[:type] == BETA_VERSION
      redirect_to settings_user_access_tokens_path
    else
      # Temporary join used to filter out bad data in the DB where an access has no authorization.
      # Eventually this join can be removed when the bad data in the DB is cleaned up.
      # https://github.com/github/github/issues/117741
      personal_tokens = current_user
        .oauth_accesses.personal_tokens
        .joins(:authorization).order(created_at: :desc)
        .paginate(page: current_page, per_page: PER_PAGE)

      render "oauth_tokens/index", locals: { tokens: personal_tokens }
    end
  end

  def new
    context_region_preset :developer_settings

    scopes = params[:scopes].to_s.split(",")
    @access = OauthAccessTokens::Domain::build(current_user.id, params[:description], params[:default_expires_at], scopes)

    render "oauth_tokens/new"
  end

  def create
    hash = params[:oauth_access]
    normalized_scopes = normalize_scopes_from(hash[:scopes])
    result = OauthAccessTokens.domain.create_personal(current_user.id, hash[:description], normalized_scopes,
      hash[:default_expires_at], hash[:custom_expires_at], allow_custom_default_expires_at?)
    case result
    when GH::Result::Ok
      @access = result.value.token_record
      token = result.value.token_value

      if scopes_normalized?(hash[:scopes], normalized_scopes)
        flash[:notice] = NORMALIZED_MESSAGE
      end

      flash[:new_personal_access] = { id: @access.id, token: token }
      instrument_emu_omboarding_pat_complete
      redirect_to settings_user_tokens_path
    when GH::Result::Error::Unprocessable
      @access = result.items.first
      flash.now[:error] = result.message
      render "oauth_tokens/new"
    end
  end

  def show
    @access = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)
    return(render_404) unless @access

    @access.default_expires_at = @access.expires_at ? "custom" : "none"
    @access.custom_expires_at = @access.expires_at

    render "oauth_tokens/show"
  end

  def update
    @access = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)
    return render_404 unless @access

    hash = params[:oauth_access]
    normalized_scopes = normalize_scopes_from(hash[:scopes])
    update_data = { "scopes" => normalized_scopes, "note" => hash[:description], "description" => hash[:description] }
    result = OauthAccessTokens.domain.update(@access.id, current_user.id, update_data)

    if scopes_normalized?(hash[:scopes], normalized_scopes)
      flash[:notice] = NORMALIZED_MESSAGE
    end

    case result
    when GH::Result::Ok
      @access = result.value
      redirect_to settings_user_tokens_path
    when GH::Result::Error
      flash[:error] = FAILURE_MESSAGE
      render "oauth_tokens/show"
    else
      render "oauth_tokens/show"
    end
  end

  def regenerate_edit # rubocop:todo GitHub/UseRestfulActions
    @access = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)
    return render_404 unless @access

    @index_page = params[:index_page]

    render "oauth_tokens/regenerate_edit"
  end

  def regenerate # rubocop:todo GitHub/UseRestfulActions
    @access = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)
    return render_404 unless @access

    result = OauthAccessTokens.domain.regenerate_with_expiry(
      @access.id,
      params.dig(:oauth_access, :default_expires_at),
      params.dig(:oauth_access, :custom_expires_at),
      allow_custom_default_expires_at?
    )

    case result
    when GH::Result::Ok
      # Unpack the result value - access and token
      @access, token = result.value

      GitHub.dogstats.increment("oauth_tokens.regenerate", tags: ["result:success"])
      flash[:new_personal_access] = { id: @access.id, token: token }
    when GH::Result::Error::Unprocessable
      @access = result.items.first

      flash.now[:error] = if result.message.present?
        "Your token is invalid due to the following issues: #{result.message}. Please resolve these issues and try again."
      else
        "An error occurred when regenerating this token, please try again"
      end
      return render "oauth_tokens/regenerate_edit"
    end

    if !params[:index_page].blank?
      redirect_to settings_user_tokens_path(page: params[:index_page])
    else
      redirect_to settings_user_token_path(@access)
    end
  end

  def destroy
    access = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)
    return render_404 unless access

    OauthAccessTokens.domain.destroy(access.id, :web_user, entry_point: :oauth_tokens_controller_destroy)

    if request.xhr?
      head 200
    else
      redirect_to settings_user_tokens_path
    end
  end

  def revoke_all # rubocop:todo GitHub/UseRestfulActions
    if OauthAccessTokens.domain.personal_tokens_count(current_user.id) > MAXIMUM_TOKENS_REVOKE_ALL
      current_user.async_revoke_oauth_tokens(:personal_tokens)
      flash[:notice] = "Revoking all personal access tokens"
    else
      current_user.revoke_oauth_tokens(:personal_tokens)
      flash[:notice] = "Revoked all personal access tokens"
    end
    redirect_to settings_user_tokens_path
  end

  def remove_authorization # rubocop:todo GitHub/UseRestfulActions
    token = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)
    return render_404 unless token
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
    normalized_scopes = OauthAccessTokens::Domain.normalize_scopes(scopes)

    if scopes&.include?("site_admin") && current_user&.site_admin_scope_allowed?
      normalized_scopes << "site_admin"
    end

    # Ensure the correct order and remove any duplicate scopes.
    OauthAccessTokens::Domain.normalize_scopes(normalized_scopes, visibility: :all)
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
    raise e unless user_facing_error?(access)

    message =
      if access.errors.any?
        access.errors.full_messages.to_sentence
      else
        e.message
      end

    [nil, message]
  end

  def allow_custom_default_expires_at?
    current_user.enterprise_managed_business.present? && ProgrammaticAccessTokenLifetimeConfiguration.expiration_limit_for(current_user.enterprise_managed_business, ProgrammaticAccessTokenType::Classic)
  end

  def user_facing_error?(access)
    has_error?(access, :note, [:github_token_prefix, :taken]) || has_error?(access, :base, [:invalid_expiration])
  end

  def has_error?(access, field, errors = [])
    access.errors.details[field].any? { |e| errors.include?(e[:error]) }
  end

  def instrument_emu_omboarding_pat_complete
    return unless ActiveModel::Type::Boolean.new.cast(params[:emu_onboarding])
    enterprise = current_user.enterprise_managed_business
    return unless enterprise&.trial?

    GitHub.logger.info(
      "info.message": "EMU onboarding PAT complete",
      "gh.business_id": enterprise.id,
      "gh.business_slug": enterprise.slug,
    )
  end
end
