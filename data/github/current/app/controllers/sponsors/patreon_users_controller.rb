# typed: strict
# frozen_string_literal: true

class Sponsors::PatreonUsersController < ApplicationController
  DELAY_IN_MINUTES_FOR_MAINTAINER_SYNC = 3

  before_action :sponsors_required
  before_action :login_required
  before_action do
    T.bind(self, Sponsors::PatreonUsersController)
    check_trade_compliance(sdn_redirect: true)
  end
  before_action :set_redirect_session, only: [:new, :destroy]
  before_action :validate_user_connecting_to_patreon, except: [:update]
  before_action :validate_become_sponsor_patreon, only: :new
  before_action :validate_patreon_state, only: :show
  before_action :require_sponsors_patreon_user_modifiable, only: [:update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :show],
    optional: true

  sig { void }
  def new
    patreon_state = SecureRandom.hex
    user_or_org = T.must_because(user_connecting_to_patreon) { "#validate_user_connecting_to_patreon" }
    session[:user_id_connecting_to_patreon] = user_or_org.id
    session[:patreon_state] = patreon_state

    # reset session state
    session[:sponsorable_login] = nil
    session[:connecting_as_sponsorable] = nil

    if for_sponsorable?
      session[:connecting_as_sponsorable] = true
      redirect_to SponsorsPatreonClient.auth_url_for_sponsorable(state: patreon_state)
    else
      session[:sponsorable_login] = params[:sponsorable_login]
      campaign_id = campaign_id_for_user

      if params[:sponsorable_login].present? && campaign_id.present?
        redirect_to SponsorsPatreonClient.become_patreon_url(
          campaign_id: campaign_id,
          state: patreon_state,
          min_cents: min_cents,
        )
      else
        redirect_to SponsorsPatreonClient.auth_url_for_sponsor(state: patreon_state)
      end
    end
  end

  sig { void }
  def show
    token_result = begin
      SponsorsPatreonClient.get_token(patreon_params[:code])
    rescue SponsorsPatreonClient::Error, SponsorsPatreonClient::UnauthorizedError => err
      flash[:error] = err.message
      return redirect_based_on_referrer
    end

    access_token = T.cast(token_result["access_token"], String)
    refresh_token = T.cast(token_result["refresh_token"], String)
    if access_token.blank? || refresh_token.blank?
      flash[:error] = "Something went wrong trying to connect with Patreon. Please try again."
      return redirect_based_on_referrer
    end

    # So we can sync the user's Patreon data
    sponsors_patreon_user.patreon_access_token = access_token
    sponsors_patreon_user.patreon_refresh_token = refresh_token

    client = SponsorsPatreonClient.new(access_token: access_token, refresh_token: refresh_token)

    identity_result = begin
      client.get_identity
    rescue SponsorsPatreonClient::Error => err
      flash[:error] = err.message
      return redirect_based_on_referrer
    end

    sponsors_patreon_user.assign_from_identity_response(identity_result)

    success = ActiveRecord::Base.connected_to(role: :writing) { sponsors_patreon_user.save }

    if success
      flash[:notice] = for_become_patron? ? successful_become_patron_message : successful_patreon_connection_message

      expires_in = T.cast(token_result["expires_in"], Integer)
      sponsors_patreon_user.enqueue_refresh_tokens_job(expires_in: expires_in)

      # Sync the sponsorable user's data so we don't have to wait for webhooks to fire. Wait a short time for any
      # new pledges on Patreon to be activated. This will only be called if this route is hit after a user/org
      # becomes a sponsor.
      sponsorable_patreon_user&.sync_sponsors_patreon_user(delay_in_minutes: DELAY_IN_MINUTES_FOR_MAINTAINER_SYNC)

      if sponsors_patreon_user_owner&.sponsorable?
        begin
          # Call the non-job version of this method so we can quickly let the sponsorable user know if they can get
          # sponsors via patreon
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: sponsors_patreon_user)
        rescue SyncSponsorsPatreonUser::UnprocessableError => err
          GitHub.logger.info("Could not sync sponsors_patreon_user with id #{sponsors_patreon_user.id}: #{err.message}")
        end
      end
    else
      flash[:error] = "Could not connect with Patreon: #{sponsors_patreon_user_error_message}"
    end

    redirect_based_on_referrer(become_patron_success: success)
  end

  sig { void }
  def destroy
    if sponsors_patreon_user.nil? || sponsors_patreon_user.destroy
      flash[:notice] = "Successfully disconnected #{whose_account} GitHub account from Patreon."
    else
      flash[:error] = "Could not disconnect from Patreon: #{sponsors_patreon_user_error_message}"
    end

    redirect_based_on_referrer
  end

  sig { void }
  def update
    if sponsors_patreon_user.update(spu_params)
      enabled_as_sponsorable = ActiveModel::Type::Boolean.new.cast(spu_params[:enabled_as_sponsorable])

      # If the user is enabling sponsorships as a sponsorable we need to initiate a sync to obtain
      # the latest membership data from Patreon. Else we can just cancel the sponsorships.
      if enabled_as_sponsorable
        sponsors_patreon_user.sync_sponsors_patreon_user(include_sponsorships: true)
      else
        sponsors_patreon_user.clean_up_sponsorships
        CleanUpPatreonWebhooksJob.perform_later(sponsors_patreon_user)
      end

      flash[:notice] = "Successfully updated @#{sponsors_patreon_user_owner}'s Patreon settings"
    else
      flash[:error] = "Something went wrong while trying to update @#{sponsors_patreon_user_owner}'s " \
        "Patreon settings"
    end

    redirect_to :back
  end

  private

  sig { returns ActionController::Parameters }
  memoize def patreon_params
    params.permit(:code, :state, :error)
  end

  sig { returns SponsorsPatreonUser }
  memoize def sponsors_patreon_user
    spu = if params[:action] == "update" && params[:id]
      SponsorsPatreonUser.find(params[:id])
    else
      user_connecting_to_patreon&.sponsors_patreon_user || SponsorsPatreonUser.new(user: user_connecting_to_patreon)
    end
    spu.actor = current_user
    spu
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
  memoize def sponsors_patreon_user_owner
    sponsors_patreon_user.user
  end

  sig { void }
  def require_sponsors_patreon_user_modifiable
    render_404 unless sponsors_patreon_user_owner&.adminable_by?(current_user)
  end

  sig { returns String }
  def sponsors_patreon_user_error_message
    sponsors_patreon_user.errors.full_messages.to_sentence(words_connector: ". ", two_words_connector: ". ") + "."
  end

  sig { returns T::Boolean }
  def disconnecting?
    params[:action] == "destroy"
  end

  sig { void }
  def validate_user_connecting_to_patreon
    user_or_org = user_connecting_to_patreon
    unless user_or_org
      return render_404 if disconnecting?

      flash[:error] = "Please choose which account to connect with Patreon."
      return redirect_based_on_referrer
    end

    unless user_or_org.adminable_by?(current_user)
      return render_404 if disconnecting?

      flash[:error] = "You don't have permission to connect this account with Patreon."
      return redirect_based_on_referrer
    end

    if for_sponsorable? && !disconnecting?
      sponsors_listing = user_or_org.sponsors_listing
      if sponsors_listing.nil? || sponsors_listing.banned?
        flash[:error] = "The specified account cannot be connected as a GitHub Sponsors maintainer."
        redirect_based_on_referrer
      end
    end
  end

  sig { returns T.nilable(T.any(GitHubSponsors::Types::Sponsorable, GitHubSponsors::Types::Sponsor)) }
  memoize def user_connecting_to_patreon
    case params[:action]
    when "new", "destroy"
      if for_sponsorable?
        User.find_by_login(params[:sponsorable])
      elsif params[:sponsor].present?
        User.find_by_login(params[:sponsor])
      elsif params[:sponsorable_login].present?
        current_user
      end
    when "show"
      if session[:user_id_connecting_to_patreon].present?
        User.find_by(id: session[:user_id_connecting_to_patreon])
      else
        current_user
      end
    end
  end

  sig { returns String }
  def successful_patreon_connection_message
    "Successfully connected #{whose_account} GitHub account with Patreon."
  end

  sig { returns String }
  def successful_become_patron_message
    "Successfully connected #{whose_account} GitHub account and pledge started. This may take a moment to show up " \
      "on GitHub."
  end

  sig { returns String }
  def whose_account
    user_or_org = user_connecting_to_patreon
    return "" unless user_or_org
    user_or_org.user? ? "your" : "@#{user_or_org.display_login}'s"
  end

  sig { returns T::Boolean }
  memoize def for_sponsorable?
    case params[:action]
    when "new", "destroy"
      params[:sponsorable].present?
    when "show"
      if session[:connecting_as_sponsorable].present?
        connecting_as_sponsorable = session[:connecting_as_sponsorable]
        session[:connecting_as_sponsorable] = nil
        connecting_as_sponsorable
      else
        false
      end
    else
      false
    end
  end

  sig { returns T::Boolean }
  def for_become_patron?
    session[:sponsorable_login].present?
  end

  sig { params(become_patron_success: T::Boolean).void }
  def redirect_based_on_referrer(become_patron_success: false)
    if for_become_patron?
      redirect_to sponsorable_path(session[:sponsorable_login],
        sponsor: user_connecting_to_patreon,
        frequency: :patreon,
        success: become_patron_success ? true : nil,
      )
    else
      safe_redirect_to redirect_url_from_referrer, fallback: settings_account_preferences_path(reload: true)
    end
  end

  sig { returns String }
  def redirect_url_from_referrer
    uri = begin
      URI.parse(session[:patreon_redirect_to].presence || request.referrer)
    rescue URI::InvalidURIError
      nil
    end
    return settings_account_preferences_path(reload: true) unless uri

    # add the reload param if going to account preferences
    # to prevent stale data in the patreon button
    params = uri.query.present? ? CGI.parse(uri.query) : {}
    params[:reload] = true if uri.path == settings_account_preferences_path
    uri.query = params.any? ? URI.encode_www_form(params) : nil
    uri.to_s
  end

  sig { void }
  def validate_patreon_state
    if patreon_params[:error].present? || patreon_params[:state].blank? ||
        patreon_params[:state] != session[:patreon_state]
      flash[:error] = "Something went wrong trying to connect with Patreon. Please try again."
      redirect_based_on_referrer
    end
    session[:patreon_state] = nil
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsor, GitHubSponsors::Types::Sponsorable, User, Symbol) }
  def target_for_conditional_access
    user_connecting_to_patreon || current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { void }
  def validate_become_sponsor_patreon
    return if params[:sponsorable_login].blank?

    return render_404 if campaign_id_for_user.blank?

    if sponsorable.nil? || !T.must(sponsorable).sponsorable_by?(user_connecting_to_patreon)
      flash[:error] = "You can't perform that action at this time."
      return redirect_based_on_referrer
    end

    if sponsorable_patreon_user && !T.must(sponsorable_patreon_user).valid_patreon_amount?(min_cents)
      pretty_amount = Billing::Money.new(min_cents).format(no_cents_if_whole: true)
      flash[:error] = "#{pretty_amount} is not a valid amount for a sponsorship of @#{sponsorable}."
      redirect_based_on_referrer
    end
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
  memoize def sponsorable
    login = params[:sponsorable_login].presence || session[:sponsorable_login]
    User.find_by_login(login) if login.present?
  end

  sig { returns T.nilable(String) }
  memoize def campaign_id_for_user
    return unless sponsorable_patreon_user

    valid_campaign_ids = T.must(sponsorable_patreon_user).patreon_campaign_ids
    return params[:campaign_id] if params[:campaign_id].present? && valid_campaign_ids.include?(params[:campaign_id])

    valid_campaign_ids.first
  end

  sig { returns Integer }
  memoize def min_cents
    cents = params[:cents]
    if cents.present?
      cents.to_i
    else
      sponsorable_patreon_user&.min_patreon_tier_amount_in_cents || 1_00
    end
  end

  sig { returns T.nilable(SponsorsPatreonUser) }
  memoize def sponsorable_patreon_user
    spu = sponsorable&.sponsors_patreon_user
    spu.actor = current_user if spu
    spu
  end

  sig { void }
  def set_redirect_session
    session[:patreon_redirect_to] = request.referrer
  end

  sig { returns ActionController::Parameters }
  def spu_params
    params.require(:sponsors_patreon_user).permit(:enabled_as_sponsorable)
  end
end
