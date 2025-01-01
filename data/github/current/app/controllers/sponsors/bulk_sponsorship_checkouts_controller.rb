# typed: strict
# frozen_string_literal: true

class Sponsors::BulkSponsorshipCheckoutsController < ApplicationController
  include ActionView::Helpers::NumberHelper
  include Sponsors::SharedControllerMethods

  # Required for the credit card edit form
  javascript_bundle :billing

  SPONSORABLES_TO_DISPLAY = 10
  BATCH_SIZE = 20

  before_action :add_csp_exceptions, only: [:show, :create]
  before_action :login_required
  before_action :ensure_user_has_verified_email
  before_action :valid_sponsor_required
  before_action do
    T.bind(self, Sponsors::BulkSponsorshipCheckoutsController)
    check_trade_compliance(target: sponsor,
      redirect_url: sponsors_explore_index_path(account: sponsor), sdn_redirect: true)
  end
  before_action :require_data_for_show, only: [:show]
  before_action :require_data_for_create, only: [:create]
  before_action :ensure_multiple_sponsorships

  javascript_bundle :sponsors
  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  # For editing billing information within a modal
  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
    frame_src: [GitHub.zuora_payment_page_server].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def show
    render_show
  end

  sig { void }
  def create
    if dry_run?
      this_sponsor.save_bulk_sponsorship_import(amounts_by_sponsorable_login_array)

      redirect_to sponsors_bulk_sponsorship_checkout_path(
        sponsor: this_sponsor,
        frequency: frequency_param,
        pay_prorated: params[:pay_prorated],
        active_on: params[:active_on],
      )
    elsif bulk_sponsorships_result.success?
      enqueue_remaining_batches_if_necessary
      flash[:notice] = success_message
      render "sponsors/bulk_sponsorship_checkouts/success", locals: {
        sponsor: sponsor,
        total_sponsored: bulk_sponsorships_result.total_sponsored,
        total_amount: bulk_sponsorships_result.total_amount_excluding_fees,
        any_sponsored_orgs: bulk_sponsorships_result.any_sponsored_organizations?,
        any_sponsored_users: bulk_sponsorships_result.any_sponsored_users?,
        frequency: one_time_payments? ? :one_time : :recurring,
      }
    else
      show_errors
      render_show
    end
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsor) }
  def this_sponsor
    T.must_because(sponsor) { "#valid_sponsor_required ensures non-nil" }
  end

  sig { returns T::Boolean }
  def one_time_payments?
    frequency == :one_time
  end

  sig { returns(String) }
  def render_show
    render "sponsors/bulk_sponsorship_checkouts/show", locals: {
      sponsor: sponsor,
      valid_sponsorship_rows: valid_sponsorship_rows,
      sponsorship_count: valid_sponsorship_rows.size,
      form_data: Sponsors::BulkSponsorshipRow.form_data_for(valid_sponsorship_rows, for_checkout: true),
      privacy_level: privacy_level,
      opted_in_to_email: opted_in_to_email?,
      frequency: frequency,
      active_on: active_on,
      pay_prorated: pay_prorated?,
    }
  end

  sig { returns T::Boolean }
  memoize def dry_run?
    params[:confirm] != "1"
  end

  sig { returns(Symbol) }
  memoize def frequency
    frequency_param == "recurring" ? :recurring : :one_time
  end

  sig { returns T::Hash[T.untyped, T.untyped] }
  memoize def bulk_sponsorship_params
    sponsorable_logins = params[:sponsorables]
    return {} if sponsorable_logins.blank?

    # Keep this parameter structure in sync with fields produced by
    # Sponsors::BulkSponsorshipRow.form_data_for as well as in
    # app/components/billing/settings/responsor_button_component.html.erb
    all_bulk_sponsorships = params.require(:bulk_sponsorship).permit(
      sponsorable_logins.map { |login| [login.downcase, [:amount, :amount_with_fee, :include]] }.to_h
    ).to_h

    all_bulk_sponsorships.select { |_, data| data[:include] == "1" }
  end

  sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }] }
  memoize def saved_import
    sponsor&.amounts_by_sponsorable_login_bulk_sponsorship_import || []
  end

  sig { returns T::Hash[String, T.any(String, Integer)] }
  memoize def amounts_by_sponsorable_login
    bulk_sponsorship_params.map { |login, data| [login, data[:amount]] }.to_h
  end

  sig { returns T::Hash[String, T.any(String, Integer)] }
  memoize def amounts_by_sponsorable_login_in_first_batch
    logins_in_batch = amounts_by_sponsorable_login.keys.take(BATCH_SIZE)
    T.unsafe(amounts_by_sponsorable_login).slice(*logins_in_batch)
  end

  sig { returns T::Array[T::Hash[String, T.any(String, Integer)]] }
  def remaining_amounts_by_sponsorable_login_batches
    remaining_logins = amounts_by_sponsorable_login.keys - amounts_by_sponsorable_login_in_first_batch.keys
    remaining_logins.each_slice(BATCH_SIZE).map do |logins_in_batch|
      T.unsafe(amounts_by_sponsorable_login).slice(*logins_in_batch)
    end
  end

  sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }] }
  memoize def amounts_by_sponsorable_login_array
    if bulk_sponsorship_params.empty?
      saved_import
    else
      bulk_sponsorship_params.map { |login, data| { sponsorable_login: login, amount: data[:amount] } }
    end
  end

  sig { returns T.any(String, Symbol) }
  memoize def privacy_level
    if Sponsorship.privacy_levels.key?(params[:privacy_level])
      params[:privacy_level]
    else
      "public"
    end
  end

  sig { returns T::Boolean }
  def opted_in_to_email?
    params[:email_opt_in] == "on"
  end

  sig { returns T.any(Sponsors::CreateRecurringSponsorships::Result, Sponsors::AddOneTimePayments::Result) }
  memoize def bulk_sponsorships_result
    if one_time_payments?
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: current_user,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login_in_first_batch,
        privacy_level: privacy_level,
        receive_email: opted_in_to_email?,
      )
    else
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: current_user,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login_in_first_batch,
        privacy_level: privacy_level,
        receive_email: opted_in_to_email?,
        active_on: active_on,
        end_date: end_date,
        pay_prorated: pay_prorated?
      )
    end
  end

  sig { returns T::Boolean }
  memoize def enqueue_remaining_batches?
    multiple_batches? && bulk_sponsorships_result.success?
  end

  sig { returns T::Boolean }
  def multiple_batches?
    amounts_by_sponsorable_login.size > BATCH_SIZE
  end

  sig { void }
  def enqueue_remaining_batches_if_necessary
    return unless enqueue_remaining_batches?

    remaining_amounts_by_sponsorable_login_batches.each do |batch_of_amounts_by_sponsorable_login|
      if one_time_payments?
        SponsorsAddOneTimePaymentsJob.perform_later(
          sponsor: this_sponsor,
          actor: current_user,
          amounts_by_sponsorable_login: batch_of_amounts_by_sponsorable_login,
          privacy_level: privacy_level,
          receive_email: opted_in_to_email?,
        )
      else
        SponsorsCreateRecurringSponsorshipsJob.perform_later(
          sponsor: this_sponsor,
          actor: current_user,
          amounts_by_sponsorable_login: batch_of_amounts_by_sponsorable_login,
          privacy_level: privacy_level,
          receive_email: opted_in_to_email?,
          active_on: active_on,
          pay_prorated: pay_prorated?
        )
      end
    end
  end

  sig { returns T.nilable(String) }
  memoize def success_message
    total = bulk_sponsorships_result.total_sponsored
    return unless total.positive?

    who = this_sponsor.organization? ? this_sponsor.safe_profile_name : "You"
    unit = one_time_payments? ? "payment" : "sponsorship"
    units = unit.pluralize(total)
    frequency_adjective = if one_time_payments?
      "one-time"
    else
      "monthly"
    end
    maintainer_units = total == 1 ? "a maintainer" : "maintainers"
    prefix = "#{who} made #{number_with_delimiter(total)} #{frequency_adjective} #{units} to #{maintainer_units}!"
    suffix = if enqueue_remaining_batches?
      " Hang tight, we'll process the rest soon."
    end
    "#{prefix}#{suffix}"
  end

  sig { returns String }
  def error_message
    error_list = bulk_sponsorships_result.errors.join(", ")
    if success_message
      "#{success_message} However, there were also some problems: #{error_list}"
    else
      error_list
    end
  end

  sig { void }
  def ensure_user_has_verified_email
    if current_user.no_verified_emails?
      flash[:error] = "You need a verified email address in order to sponsor anyone."
      redirect_to sponsors_explore_index_path(sponsor: sponsor)
    end
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsor, Symbol) }
  def target_for_conditional_access
    sponsor || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { void }
  def require_data_for_show
    return if saved_import.present?

    flash[:error] = "No bulk sponsorship data was provided."
    redirect_to new_sponsors_bulk_sponsorship_imports_path(redirect_params)
  end

  sig { void }
  def require_data_for_create
    if params[:bulk_sponsorship].blank?
      flash[:error] = "No bulk sponsorship data was provided."
      return redirect_to new_sponsors_bulk_sponsorship_imports_path(redirect_params)
    end

    if params[:sponsorables].blank?
      who = this_sponsor.organization? ? this_sponsor.login : "you"
      flash[:error] = "Please specify who #{who} would like to sponsor."
      return redirect_to new_sponsors_bulk_sponsorship_imports_path(redirect_params)
    end

    amounts = bulk_sponsorship_params.map { |_, data| data[:amount] }
    if amounts.any?(&:blank?)
      flash[:error] = "Please specify a sponsorship amount for each maintainer."
      redirect_to new_sponsors_bulk_sponsorship_imports_path(redirect_params)
    end
  end

  sig { void }
  def show_errors
    flash[:error] = if sponsor&.has_valid_payment_method_for_sponsorships?
      error_message
    else
      "Please specify a payment method to be able to bulk sponsor."
    end
  end

  sig { returns T::Array[Sponsors::BulkSponsorshipRow] }
  memoize def valid_sponsorship_rows
    Sponsors::BulkSponsorshipRow.build_rows_from_params(
      amounts_by_sponsorable_login_array: amounts_by_sponsorable_login_array,
      sponsor: this_sponsor,
      recurring: !one_time_payments?,
    ).select(&:valid?)
  end

  sig { void }
  def ensure_multiple_sponsorships
    return if valid_sponsorship_rows.size >= 2

    valid_sponsorship_row = valid_sponsorship_rows.first
    if valid_sponsorship_row
      sponsorable_login = valid_sponsorship_row.sponsorable_login
      tier = valid_sponsorship_row.published_tier

      if tier
        redirect_to sponsorable_sponsorships_path(
          sponsorable_login,
          tier_id: tier.id,
          preview: false,
          **redirect_params
        )
      else
        redirect_to sponsorable_sponsorships_path(
          sponsorable_login,
          preview: false,
          amount: valid_sponsorship_row.dollars,
          **redirect_params
        )
      end
    else
      flash[:error] = "No bulk sponsorship data was provided."
      redirect_to new_sponsors_bulk_sponsorship_imports_path(redirect_params)
    end
  end

  sig { returns T::Hash[String, T.any(T.nilable(String), GitHubSponsors::Types::Sponsor)] }
  def redirect_params
    {
      sponsor: this_sponsor,
      # default to `one-time` if frequency is not specified, so we redirect
      # to the correct one-time checkout when only a single maintainer is specified
      frequency: frequency_param || "one-time",
    }
  end

  sig { returns(T::Boolean) }
  memoize def pay_prorated?
    return false if one_time_payments?
    return true unless this_sponsor.can_skip_sponsorship_proration?

    if params.key?(:pay_prorated)
      params[:pay_prorated] == "true"
    else
      this_sponsor.sponsors_prorated_by_default?
    end
  end

  sig { returns(T.nilable(Date)) }
  memoize def active_on
    return unless this_sponsor.can_schedule_sponsorships?

    begin
      Date.iso8601(params[:active_on])
    rescue Date::Error
      nil
    end
  end

  sig { returns(T.nilable(Date)) }
  def end_date
    return unless frequency == :recurring
    return unless params[:set_expires_at] == "1"
    year = end_date_params[:year].to_i
    month = end_date_params[:month].to_i
    Date.new(year, month, 1).end_of_month
  end

  sig { returns(ActionController::Parameters) }
  memoize def end_date_params
    params.require(:end_date).permit(:month, :year)
  end
end
