# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::DependenciesController < Orgs::Sponsorings::BaseController
  include ProfilesHelper

  before_action :ensure_user_can_access
  before_action :add_csp_exceptions, only: [:show]
  before_action :sponsors_required
  before_action :viewer_can_manage_sponsorships

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  class Dependency < T::Struct
    const :name, String
    const :fullRepoName, String
  end

  class SponsorableData < T::Struct
    const :id, Integer
    const :sponsorableName, String
    const :dependenciesArray, T::Array[Dependency]
    const :dependencyCount, Integer
    const :sponsorableAvatarUrl, String
    const :sponsorableIsOrg, T::Boolean
    const :recentActivity, T.nilable(String)
    const :viewerIsSponsor, T.nilable(T::Boolean)
  end

  class ReactProps < T::Struct
    const :sponsorableDependencies, T::Array[SponsorableData]
    const :orgName, String
    const :viewerPrimaryEmail, T.nilable(String)
  end

  CSP_EXCEPTIONS = T.let({
    connect_src: ["https://api.securityscorecards.dev"] }, T::Hash[Symbol, T::Array[String]])

  sig { returns(T::Array[SponsorableData]) }
  def index
    @org = T.let(this_organization, T.untyped)
    @explore_loader = T.let(SponsorsExploreLoader.new(org: @org, viewer: current_user), T.untyped)
    @sponsorables = T.let(@explore_loader.sponsorables_from_dependencies, T.untyped)

    search_term = params[:search_term]
    search_term_downcase = search_term.downcase

    results = search_matching_sponsorables(search_term_downcase)

    respond_to do |format|
      format.json { render json: results }
    end
  end

  sig { void }
  def show
    @org = T.let(this_organization, T.untyped)
    filter_set = SponsorsExploreFilterSet.new(account_login: @org&.display_login, per_page: 10)
    @explore_loader = T.let(SponsorsExploreLoader.new(filter_set: filter_set, org: @org, viewer: current_user), T.untyped)

    # Since we're using a React partial, we want to get all sponsorables for this org in Rails.
    # We'll then pass this data to the React partial, which will handle the pagination.
    @sponsorables = T.let(@explore_loader.sponsorables_from_dependencies, T.untyped)
    @total_sponsorable_dependencies = T.let(@explore_loader.total_results, T.untyped)

    respond_to do |format|
      format.html do
        render "orgs/sponsorings/dependencies/show", locals: {
          sponsor: this_organization,
          react_partial_props: react_partial_props
        }
      end
    end
  end

  private

  sig { params(search_term_downcase: String).returns(T::Array[SponsorableData]) }
  def search_matching_sponsorables(search_term_downcase)
    matching_sponsorables_by_dependency = @sponsorables.select do |sponsorable|
      dependencies = @explore_loader.all_dependencies_represented_by_sponsorable(sponsorable.id)
      dependencies.any? { |dependency| dependency.name.downcase.include?(search_term_downcase) }
    end

    matching_sponsorables = @sponsorables.select do |sponsorable|
      sponsorable.name.downcase.include?(search_term_downcase)
    end

    combined_matching_sponsorables = (matching_sponsorables | matching_sponsorables_by_dependency)

    if combined_matching_sponsorables.empty?
      results = []
    else
      results = serialized_sponsoring_dependencies(combined_matching_sponsorables)
    end
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def react_partial_props
    ReactProps.new(
      sponsorableDependencies: serialized_sponsoring_dependencies(@sponsorables),
      orgName: @org.display_login,
      viewerPrimaryEmail: current_user.email
    ).serialize
  end

  sig { params(sponsorables: T.untyped).returns T::Array[SponsorableData] }
  def serialized_sponsoring_dependencies(sponsorables)
    sponsorables = build_sponsorables_dependencies(sponsorables)
    serialized_sponsorships = sponsorables.map { |sponsorable| serialize_sponsoring_dependency(sponsorable: sponsorable) }
  end

  sig { params(sponsorable: T.untyped).returns(Orgs::Sponsorings::DependenciesController::SponsorableData) }
  def serialize_sponsoring_dependency(sponsorable:)
    dependencies_array = sponsorable[:dependenciesArray].map do |dependency|
      Dependency.new(
        name: dependency[:name],
        fullRepoName: dependency[:full_repo_name],
      )
    end

    SponsorableData.new(
      id: sponsorable[:id],
      sponsorableName: sponsorable[:sponsorableName],
      dependenciesArray: dependencies_array,
      dependencyCount: sponsorable[:dependencyCount],
      sponsorableAvatarUrl: sponsorable[:sponsorableAvatarUrl],
      sponsorableIsOrg: sponsorable[:sponsorableIsOrg],
      recentActivity: sponsorable[:recentActivity],
      viewerIsSponsor: viewer_active_sponsorable_ids.include?(sponsorable[:id])
    )
  end

  sig { params(sponsorables: T.untyped).returns(T::Array[SponsorableData]) }
  def build_sponsorables_dependencies(sponsorables)
    # We're not actually needing paginated dependencies here, but it makes sense to reuse the method
    # We only need 2 dependencies per sponsorable to be returned, so we'll set the filter to return 2 in this case
    filter_set_return_2 = SponsorsExploreFilterSet.new(account_login: @org&.display_login, per_page: 2)
    explore_loader_return_2 = SponsorsExploreLoader.new(filter_set: filter_set_return_2, org: @org, viewer: current_user)

    sponsorables_dependencies_list = []
    sponsorables.each do |sponsorable|
      recent_activity_date = nil

      if sponsorable.type == "User"
        past_year = Contribution::Calendar.time_range_ending_on(Time.zone.now)
        time_range ||= past_year
        collector = Contribution::Collector.new(
          time_range: time_range,
          user: sponsorable,
          viewer: @org,
        )
        recent_activity_date = date_range_in_time_zone(collector)&.last&.strftime("%b %-d, %Y")
      elsif sponsorable.type == "Organization"
        recent_activity_date = sponsorable&.repositories&.order(pushed_at: :desc).pluck(:pushed_at).first&.strftime("%b %-d, %Y")
      end

      sponsorable.define_singleton_method(:recent_activity_date) { recent_activity_date }

      deps_per_sponsorable = explore_loader_return_2.paginated_dependencies_represented_by_sponsorable(sponsorable.id)
      total_deps = @explore_loader.total_associated_dependencies(sponsorable)
      dependencies_array = deps_per_sponsorable.map do |dep|
        {
          name: dep.to_s,
          full_repo_name: dep.name_with_display_owner
        }
      end

      sponsorables_dependencies_list << {
        id: sponsorable.id,
        sponsorableName: sponsorable&.to_s,
        dependenciesArray: dependencies_array,
        dependencyCount: total_deps,
        sponsorableAvatarUrl: sponsorable&.primary_avatar_url || "",
        sponsorableIsOrg: sponsorable&.organization? || false,
        recentActivity: sponsorable&.recent_activity_date
      }
    end
    sponsorables_dependencies_list
  end

  sig { void }
  def ensure_user_can_access
    render_404 unless this_organization.billing_manageable_by?(current_user)
  end

  sig { void }
  def viewer_can_manage_sponsorships
    render_404 if current_user.potential_sponsor_ids.exclude?(this_organization.id)
  end

  sig { returns(T::Set[Integer]) }
  memoize def viewer_active_sponsorable_ids
    sponsorable_ids = @org&.active_sponsorships_as_sponsor_relation&.map(&:sponsorable_id) || []
    Set.new(sponsorable_ids)
  end
end
