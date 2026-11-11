# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::SponsorshipsController < StafftoolsController
  before_action :sponsors_required
  before_action :invoiced_sponsor_required

  delegate :sponsorable_login, :amount_in_dollars, :is_recurring, :end_month, :end_year,
           :is_public, :email_opt_in, :sponsorable, :sponsors_listing, :end_date, :parent_tier_id,
           :active_on, :skip_proration, to: :sponsorship_form_inputs

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index, :edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit, :new], optional: true

  SPONSORSHIPS_PER_PAGE = 20

  sig { void }
  def index
    this_sponsor = T.must_because(sponsor) { "sponsor is required by before_filter" }
    sponsorships = this_sponsor.sponsorships_as_sponsor.order(created_at: :desc)
      .paginate(page: current_page, per_page: SPONSORSHIPS_PER_PAGE)

    respond_to do |format|
      format.html do
        if loading_next_page_of_results?
          render Stafftools::Sponsors::Invoiced::SponsorshipsListComponent.new(
            sponsorships: sponsorships,
            sponsor: this_sponsor,
          ), layout: false
        else
          render "stafftools/sponsors/invoiced/sponsorships/index", locals: {
            sponsor: this_sponsor,
            sponsorships: sponsorships,
          }
        end
      end
    end
  end

  sig { void }
  def new
    render "stafftools/sponsors/invoiced/sponsorships/new", locals: {
      sponsor: sponsor,
      sponsorship_form_inputs: sponsorship_form_inputs,
    }
  end

  sig { void }
  def create
    errors = sponsorship_form_input_errors || create_sponsorship
    if errors.blank?
      flash[:notice] = success_message
      redirect_to stafftools_sponsors_invoiced_sponsor_transfers_path(sponsor)
    else
      flash.now[:error] = error_message(errors)
      render "stafftools/sponsors/invoiced/sponsorships/new", locals: {
        sponsor: sponsor,
        sponsorship_form_inputs: sponsorship_form_inputs,
      }
    end
  end

  sig { void }
  def edit
    render("stafftools/sponsors/invoiced/sponsorships/edit",
      locals: { sponsor: sponsor, sponsorship_form_inputs: sponsorship_form_inputs }
    )
  end

  sig { void }
  def update
    errors = sponsorship_form_input_errors || update_sponsorship
    if errors.blank?
      flash[:notice] = success_message
      redirect_to stafftools_sponsors_invoiced_sponsor_sponsorships_path(sponsor)
    else
      flash.now[:error] = error_message(errors)
      render("stafftools/sponsors/invoiced/sponsorships/edit",
        locals: { sponsor: sponsor, sponsorship_form_inputs: sponsorship_form_inputs }
      )
    end
  end

  private

  sig { void }
  def invoiced_sponsor_required
    this_sponsor = sponsor
    return render_404 unless this_sponsor.present?
    return render_404 unless this_sponsor.is_a?(Organization)

    render_404 unless this_sponsor.premium_sponsor?
  end

  sig { returns(T::Boolean) }
  def loading_next_page_of_results?
    request.xhr? || pjax?
  end

  sig { returns(Stafftools::Sponsors::Invoiced::SponsorshipFormInputs) }
  memoize def sponsorship_form_inputs
    sponsor = T.must_because(self.sponsor) { "#invoiced_sponsor_required ensures non-nil" }

    case action_name.to_sym
    when :new
      skip_proration = sponsor.can_skip_sponsorship_proration? && !sponsor.sponsors_prorated_by_default?
      Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new(skip_proration: skip_proration)
    when :create
      Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new(**sponsorship_params)
    when :edit
      Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.from_sponsorship(sponsorship)
    when :update
      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.from_sponsorship(sponsorship)
      inputs.tap { |inputs| inputs.assign_attributes(**sponsorship_params) }
    end
  end

  sig { returns(T.nilable(String)) }
  def sponsorship_form_input_errors
    return if sponsorship_form_inputs.valid?
    sponsorship_form_inputs.errors.full_messages.to_sentence
  end

  sig { returns(String) }
  def success_message
    "Successfully #{action_name}d sponsorship from #{sponsor} to #{sponsorable}"
  end

  sig { params(errors: String).returns(String) }
  def error_message(errors)
    "Couldn‘t #{action_name} sponsorship: #{errors}"
  end

  sig { returns(T.nilable(User)) }
  memoize def sponsor
    User.find_by_login(params[:invoiced_sponsor_id])
  end

  sig { returns(T.nilable(Sponsorship)) }
  memoize def sponsorship
    Sponsorship.find_by(id: params[:id])
  end

  # Creates a sponsorship
  #
  # Returns nil if the sponsorship was created successfully, and a String error message otherwise.
  sig { returns(T.nilable(String)) }
  def create_sponsorship
    create_sponsorship_for_tier
    nil
  rescue Sponsors::CreateSponsorsTier::ForbiddenError,
    Sponsors::CreateSponsorsTier::UnprocessableError,
    Sponsors::CreateSponsorship::ForbiddenError,
    Sponsors::CreateSponsorship::UnprocessableError,
    Billing::CreateSubscriptionItem::UnprocessableError => err
    err.message
  end

  # Updates a sponsorship
  #
  # Returns nil if the sponsorship was update successfully, and a String error message otherwise.
  sig { returns(T.nilable(String)) }
  def update_sponsorship
    this_sponsorship = T.must_because(sponsorship) { "sponsorship is required by before_filter" }
    updated_sponsorship = Sponsors::UpdateSponsorshipTier.call(this_sponsorship,
      new_tier: sponsorship_tier,
      viewer: current_user,
    )

    Sponsors::UpdateSponsorshipPreferences.call(updated_sponsorship,
      viewer: current_user,
      is_public: is_public,
      email_opt_in: email_opt_in,
      end_date: end_date,
    )
    nil
  rescue Sponsors::UpdateSponsorship::ForbiddenError,
    Sponsors::UpdateSponsorship::UnprocessableError => err
    err.message
  end

  sig { returns(SponsorsTier) }
  memoize def sponsorship_tier
    Sponsors::CreateSponsorsTier.find_published_or_create_custom_tier(
      sponsors_listing: sponsors_listing,
      amount: amount_in_dollars,
      is_recurring: is_recurring,
      viewer: current_user,
      sponsor: sponsor,
      parent_tier_id: parent_tier_id,
    )
  end

  sig { returns(Sponsorship) }
  def create_sponsorship_for_tier
    sponsor = T.must_because(self.sponsor) { "#invoiced_sponsor_required ensures non-nil" }
    if sponsorship_tier.recurring?
      Sponsors::CreateRecurringSponsorship.call(
        tier: sponsorship_tier,
        sponsor: sponsor,
        sponsorable: sponsorable,
        viewer: current_user,
        is_public: is_public,
        email_opt_in: email_opt_in,
        pay_prorated: !skip_proration,
        end_date: end_date,
        active_on: active_on,
      )
    else
      Sponsors::AddOneTimePayment.call(
        tier: sponsorship_tier,
        sponsor: sponsor,
        sponsorable: sponsorable,
        viewer: current_user,
        is_public: is_public,
        email_opt_in: email_opt_in,
      )
    end
  end

  sig { returns(ActionController::Parameters) }
  def sponsorship_params
    params.require(:sponsorship).permit(
      :sponsorable_login,
      :amount_in_dollars,
      :is_recurring,
      :end_month,
      :end_year,
      :is_public,
      :email_opt_in,
      :active_on,
      :skip_proration,
    )
  end
end
