# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::PotentialSponsorshipsController < StafftoolsController
  before_action :sponsors_required
  before_action :require_potential_sponsorable, only: [:new, :edit, :create, :update, :destroy]
  before_action :require_non_spammy_potential_sponsorable, only: [:new]
  before_action :require_potential_sponsorable_to_not_have_listing, only: [:new]
  before_action :require_potential_sponsor, only: [:create, :update]
  before_action :require_existing_potential_sponsorship, only: [:edit, :update, :destroy]

  POTENTIAL_SPONSORSHIPS_PER_PAGE = 30

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index, :edit, :new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit, :new],
    optional: true

  sig { void }
  def index
    # Necessary relations will be preloaded in Stafftools::Sponsors::PotentialSponsorshipsListComponent to
    # avoid n+1 queries:
    potential_sponsorships = PotentialSponsorship.most_recent.paginate(per_page: POTENTIAL_SPONSORSHIPS_PER_PAGE,
      page: current_page)

    respond_to do |format|
      format.html do
        if request.xhr?
          render Stafftools::Sponsors::PotentialSponsorshipsListComponent.new(
            potential_sponsorships: potential_sponsorships,
          ), layout: false
        else
          render "stafftools/sponsors/potential_sponsorships/index", locals: {
            potential_sponsorships: potential_sponsorships,
          }
        end
      end
    end
  end

  sig { void }
  def new
    user_or_org = T.must_because(potential_sponsorable) { "#require_potential_sponsorable ensures non-nil" }
    potential_sponsorship = user_or_org.potential_sponsorships_as_sponsorable.new(created_by: current_user)
    render_new(potential_sponsorship)
  end

  sig { void }
  def edit
    potential_sponsorship = T.must_because(existing_potential_sponsorship) do
      "#require_existing_potential_sponsorship ensures non-nil"
    end
    render_edit(potential_sponsorship)
  end

  sig { void }
  def create
    user_or_org = T.must_because(potential_sponsorable) { "#require_potential_sponsorable ensures non-nil" }
    potential_sponsorship = user_or_org.potential_sponsorships_as_sponsorable.new(potential_sponsorship_params)
    potential_sponsorship.created_by = current_user
    potential_sponsorship.potential_sponsor = potential_sponsor

    if user_or_org.sponsors_listing
      T.unsafe(potential_sponsorship).state = :sponsors_listing_created
    end

    if potential_sponsorship.save
      flash[:notice] = "We will let #{user_or_org} know that someone would like to sponsor them."
      redirect_to stafftools_sponsors_potential_sponsorships_path
    else
      user_type = user_or_org.user? ? "user" : "organization"
      flash[:error] = "Could not record a potential sponsorship for the #{user_type}: " +
        potential_sponsorship.errors.full_messages.to_sentence
      render_new(potential_sponsorship)
    end
  end

  sig { void }
  def update
    potential_sponsorship = T.must_because(existing_potential_sponsorship) do
      "#require_existing_potential_sponsorship ensures non-nil"
    end
    potential_sponsorship.assign_attributes(potential_sponsorship_params)
    potential_sponsorship.created_by = current_user
    potential_sponsorship.potential_sponsor = potential_sponsor
    if potential_sponsorship.save
      flash[:notice] = "Details saved for potential sponsorship from #{potential_sponsor} => " \
        "#{potential_sponsorable}."
      redirect_to stafftools_sponsors_potential_sponsorships_path
    else
      flash[:error] = "Could not update the potential sponsorship: " +
        potential_sponsorship.errors.full_messages.to_sentence
      render_edit(potential_sponsorship)
    end
  end

  sig { void }
  def destroy
    potential_sponsorship = T.must_because(existing_potential_sponsorship) do
      "#require_existing_potential_sponsorship ensures non-nil"
    end
    if potential_sponsorship.destroy
      flash[:notice] = "We'll no longer show a notice to #{potential_sponsorable} that someone would like to " \
        "sponsor them."
      redirect_to stafftools_sponsors_potential_sponsorships_path
    else
      flash[:error] = "Could not remove the potential sponsorship: " +
        potential_sponsorship.errors.full_messages.to_sentence
      redirect_to edit_stafftools_user_potential_sponsorship_path(potential_sponsorable, potential_sponsorship)
    end
  end

  private

  sig { returns ActionController::Parameters }
  memoize def potential_sponsorship_params
    params.require(:potential_sponsorship).permit(:potential_sponsor_id, :message)
  end

  sig { returns T.nilable(PotentialSponsorship) }
  memoize def existing_potential_sponsorship
    if params[:id]
      user_or_org = potential_sponsorable
      return unless user_or_org
      user_or_org.potential_sponsorships_as_sponsorable.find(params[:id])
    end
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
  memoize def potential_sponsorable
    User.find_by_login(params[:user_id])
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
  memoize def potential_sponsor
    if login = params[:potential_sponsor_login]
      User.find_by_login(login)
    elsif id = potential_sponsorship_params[:potential_sponsor_id]
      User.find_by(id: id)
    end
  end

  sig { void }
  def require_potential_sponsorable
    render_404 unless potential_sponsorable
  end

  sig { void }
  def require_potential_sponsor
    render_404 unless potential_sponsor
  end

  sig { void }
  def require_non_spammy_potential_sponsorable
    render_404 if potential_sponsorable&.spammy?
  end

  sig { void }
  def require_potential_sponsorable_to_not_have_listing
    return if potential_sponsorable&.sponsors_listing.nil?

    flash[:notice] = "#{potential_sponsorable} has already signed up for Sponsors."
    redirect_to stafftools_sponsors_member_path(potential_sponsorable)
  end

  sig { void }
  def require_existing_potential_sponsorship
    render_404 unless existing_potential_sponsorship
  end

  sig { params(potential_sponsorship: PotentialSponsorship).void }
  def render_new(potential_sponsorship)
    user_or_org = T.must_because(potential_sponsorable) { "#require_potential_sponsorable ensures non-nil" }
    any_prior_acknowledged_potential_sponsorships = user_or_org
      .potential_sponsorships_as_sponsorable.with_acknowledged_state.any?
    render "stafftools/sponsors/potential_sponsorships/new", locals: {
      potential_sponsorship: potential_sponsorship,
      potential_sponsorable: user_or_org,
      any_prior_acknowledged_potential_sponsorships: any_prior_acknowledged_potential_sponsorships,
    }
  end

  sig { params(potential_sponsorship: PotentialSponsorship).void }
  def render_edit(potential_sponsorship)
    render "stafftools/sponsors/potential_sponsorships/edit", locals: {
      potential_sponsorship: potential_sponsorship,
      potential_sponsorable: potential_sponsorable,
    }
  end
end
