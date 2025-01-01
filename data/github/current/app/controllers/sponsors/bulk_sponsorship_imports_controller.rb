# typed: strict
# frozen_string_literal: true

class Sponsors::BulkSponsorshipImportsController < ApplicationController
  extend T::Sig
  include Sponsors::SharedControllerMethods

  RedirectParams = T.type_alias { T::Hash[String, T.any(T.nilable(String), GitHubSponsors::Types::Sponsor)] }

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
  only: [:edit, :new, :show]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:edit, :new, :show], optional: true

  javascript_bundle :sponsors
  stylesheet_bundle :sponsors

  CSV_PARAM_NAME = :file
  MAX_FILE_SIZE = T.let(100.kilobytes, Integer)
  MINIMUM_VALID_SPONSORSHIPS_FOR_GLOBAL_AMOUNT_EDITOR = 2

  before_action :login_required_with_return_to_explore
  before_action :valid_sponsor_required, only: [:create, :edit]
  before_action :require_data, only: [:create, :edit]
  before_action :require_valid_data, only: [:create, :edit]
  before_action only: [:new] do
    T.bind(self, Sponsors::BulkSponsorshipImportsController)
    check_trade_compliance(target: sponsor, redirect_url: sponsors_explore_index_path(account: sponsor))
  end
  before_action only: [:create, :edit] do
    T.bind(self, Sponsors::BulkSponsorshipImportsController)
    check_trade_compliance(target: sponsor,
      redirect_url: sponsors_explore_index_path(account: sponsor), sdn_redirect: true)
  end

  sig { void }
  def new
    render "sponsors/bulk_sponsorship_imports/new", locals: {
      sponsor: sponsor,
      form_data: {},
      via_file: true,
      frequency: frequency,
      redirect_params: redirect_params,
    }
  end

  sig { void }
  def show
    redirect_to_new_bulk_sponsorship_import_page
  end

  sig { void }
  def create
    sponsor = T.must_because(self.sponsor) { "#valid_sponsor_required before_action ensures not nil" }
    if sponsor.save_bulk_sponsorship_import(amounts_by_sponsorable_login_array)
      instrument_file_import if file.present?
    else
      flash[:error] = "There was an error importing your bulk sponsorships. Please try again later."
      GitHub.logger.error("Failed to save bulk sponsorship import",
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "sponsor.id": sponsor.id,
        "actor.id": current_user.id,
        "message": sponsor.bulk_sponsorship_import&.errors&.full_messages&.to_sentence,
      )
    end
    redirect_to_edit_bulk_sponsorship_import_page
  end

  sig { void }
  def edit
    render "sponsors/bulk_sponsorship_imports/edit", locals: {
      errors: validator.errors,
      valid_sponsorship_rows: valid_sponsorship_rows,
      sponsorship_rows: sponsorship_rows,
      sponsor: sponsor,
      form_data: Sponsors::BulkSponsorshipRow.form_data_for(sponsorship_rows, file_uploaded: file_uploaded?),
      via_file: file_uploaded?,
      show_global_amount_editor: show_global_amount_editor?,
      over_import_limit_rows: over_import_limit_rows,
      frequency: frequency,
      redirect_params: redirect_params,
    }
  end

  private

  sig { returns T.nilable(T::Boolean) }
  def file_uploaded?
    file.present? || ActiveModel::Type::Boolean.new.cast(params[:file_uploaded])
  end

  sig { void }
  def redirect_to_new_bulk_sponsorship_import_page
    redirect_to new_sponsors_bulk_sponsorship_imports_path(redirect_params)
  end

  sig { void }
  def redirect_to_edit_bulk_sponsorship_import_page
    redirect_to edit_sponsors_bulk_sponsorship_imports_path(redirect_params)
  end

  sig { void }
  def login_required_with_return_to_explore
    redirect_to_login(sponsors_explore_index_path) unless logged_in?
  end

  sig { returns T.nilable(ActionDispatch::Http::UploadedFile) }
  memoize def file
    params[CSV_PARAM_NAME]
  end

  sig { returns Symbol }
  def frequency
    frequency_param == "recurring" ? :recurring : :one_time
  end

  sig { void }
  def require_data
    return if bulk_sponsorship_data?

    flash[:error] = "No bulk sponsorship data was provided."
    redirect_to_new_bulk_sponsorship_import_page
  end

  sig { returns T::Boolean }
  def bulk_sponsorship_data?
    file.present? || params[:bulk_sponsorship].present? ||
      sponsor&.amounts_by_sponsorable_login_bulk_sponsorship_import.present?
  end

  sig { returns T::Hash[T.untyped, T.untyped] }
  memoize def bulk_sponsorship_params
    return {} if file.present?
    sponsorable_logins = params[:sponsorables]
    return {} if sponsorable_logins.blank?

    # Keep this parameter structure in sync with fields produced by
    # Sponsors::BulkSponsorshipRow.form_data_for as well as in
    # app/components/billing/settings/responsor_button_component.html.erb
    params.require(:bulk_sponsorship).permit(
      sponsorable_logins.map { |login| [login.downcase, [:amount, :amount_with_fee]] }.to_h
    ).to_h
  end

  sig { returns RedirectParams }
  def redirect_params
    { sponsor: sponsor, frequency: frequency_param }
  end

  sig { returns T.nilable(Sponsors::BulkSponsorshipImportProcessor::Result) }
  memoize def import_result
    return unless file
    Sponsors::BulkSponsorshipImportProcessor.call(file: T.must(file), frequency: frequency)
  end

  sig { returns Sponsors::BulkSponsorshipValidator }
  memoize def validator
    Sponsors::BulkSponsorshipValidator.new(
      sponsor: sponsor,
      actor: current_user,
      amounts_by_sponsorable_login: amounts_by_sponsorable_login,
    )
  end

  sig { returns T::Hash[String, T.any(String, Integer, Billing::Money)] }
  memoize def amounts_by_sponsorable_login
    if file.present? && import_result
      pairs = T.must(import_result).amounts_by_sponsorable_login_array.map do |element|
        [element[:sponsorable_login], element[:amount]]
      end
      pairs.to_h
    elsif sponsor&.amounts_by_sponsorable_login_bulk_sponsorship_import.present?
      T.must(sponsor).amounts_by_sponsorable_login_bulk_sponsorship_import
        .map { |element| [element[:sponsorable_login], element[:amount]] }.to_h
    else
      bulk_sponsorship_params.map { |login, data| [login, data[:amount]] }.to_h
    end
  end

  sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }] }
  memoize def amounts_by_sponsorable_login_array
    if file.present? && import_result
      T.must(import_result).amounts_by_sponsorable_login_array
    else
      list_from_params = bulk_sponsorship_params.map do |login, data|
        { sponsorable_login: login, amount: data[:amount] }
      end
      list_from_params.presence || sponsor&.amounts_by_sponsorable_login_bulk_sponsorship_import
    end
  end

  sig { returns T::Array[Sponsors::BulkSponsorshipRow] }
  memoize def valid_sponsorship_rows
    sponsorship_rows.select(&:valid?)
  end

  sig { returns T::Array[Sponsors::BulkSponsorshipRow] }
  memoize def sponsorship_rows
    sponsor = T.must_because(self.sponsor) { "#valid_sponsor_required before_action ensures not nil" }
    Sponsors::BulkSponsorshipRow.build_rows_from_params(
      amounts_by_sponsorable_login_array: amounts_by_sponsorable_login_array,
      sponsor: sponsor,
      recurring: frequency == :recurring,
    )
  end

  sig { void }
  def require_valid_data
    if file && import_result && !T.must(import_result).valid?
      flash[:error] = T.must(import_result).errors.join(", ")
      return redirect_to_new_bulk_sponsorship_import_page
    end

    if params[:bulk_sponsorship].present?
      if params[:sponsorables].blank?
        who = sponsor&.organization? ? T.must(sponsor).login : "you"
        flash[:error] = "Please specify who #{who} would like to sponsor."
        return redirect_to_new_bulk_sponsorship_import_page
      end

      amounts = bulk_sponsorship_params.map { |_, data| data[:amount] }
      if amounts.any?(&:blank?)
        flash[:error] = "Please specify an amount to sponsor each maintainer at."
        redirect_to_new_bulk_sponsorship_import_page
      end
    end
  end

  sig { returns T::Boolean }
  def show_global_amount_editor?
    valid_sponsorship_rows.size >= MINIMUM_VALID_SPONSORSHIPS_FOR_GLOBAL_AMOUNT_EDITOR
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsor, Symbol) }
  def target_for_conditional_access
    sponsor || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { void }
  def instrument_file_import
    message = {
      total_rows: amounts_by_sponsorable_login_array.count,
      total_rows_imported: sponsorship_rows.count,
      total_rows_with_error: sponsorship_rows.count - valid_sponsorship_rows.count,
      total_rows_over_limit: over_import_limit_rows.count,
      total_errors: total_error_count,
      file_error: :NONE,
      included_headers: import_result&.included_headers,
      frequency: frequency.upcase,
      error_counts: {
        self_dealing_error_count: self_dealing_row_count,
        login_missing_error_count: login_missing_row_count,
        non_sponsorable_error_count: non_sponsorable_row_count,
        duplicate_error_count: duplicated_row_count,
        locked_sponsorship_error_count: locked_sponsorship_row_count,
        max_amount_error_count: amount_over_limit_row_count,
        min_amount_error_count: amount_under_minimum_row_count,
        recurring_sponsorship_exists_error_count: conflicting_recurring_row_count,
      }
    }
    GlobalInstrumenter.instrument("sponsors.bulk_sponsorships_import", message)
  end

  sig { returns Integer }
  memoize def total_error_count
    [self_dealing_row_count, login_missing_row_count, non_sponsorable_row_count, duplicated_row_count,
      amount_over_limit_row_count, amount_under_minimum_row_count, locked_sponsorship_row_count].sum
  end

  sig { returns Integer }
  memoize def self_dealing_row_count
    sponsorship_rows.count(&:self_dealing?)
  end

  sig { returns Integer }
  memoize def non_sponsorable_row_count
    sponsorship_rows.count(&:non_sponsorable?)
  end

  sig { returns Integer }
  memoize def duplicated_row_count
    sponsorship_rows.count(&:duplicate?)
  end

  sig { returns Integer }
  memoize def locked_sponsorship_row_count
    sponsorship_rows.count(&:locked_sponsorship?)
  end

  sig { returns Integer }
  memoize def amount_over_limit_row_count
    sponsorship_rows.count { |row| !row.login_missing? && row.amount_over_limit? }
  end

  sig { returns Integer }
  memoize def amount_under_minimum_row_count
    sponsorship_rows.count { |row| !row.login_missing? && row.amount_under_minimum? }
  end

  sig { returns Integer }
  memoize def login_missing_row_count
    sponsorship_rows.count(&:login_missing?)
  end

  # We avoid processing all rows over the limit because that number is unbounded
  sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer, Billing::Money) }] }
  memoize def over_import_limit_rows
    amounts_by_sponsorable_login_array.drop(Sponsors::BulkSponsorshipValidator::MAX_SPONSORABLES)
  end

  sig { returns Integer }
  memoize def conflicting_recurring_row_count
    sponsorship_rows.count(&:conflicting_recurring_sponsorship?)
  end
end
