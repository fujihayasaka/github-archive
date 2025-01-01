# typed: strict
# frozen_string_literal: true

class Sponsors::SponsorshipsDependenciesExport
  include ProfilesHelper

  CSV_HEADERS = T.let(%w[
    maintainer_login
    your_dependencies_they_maintain_or_own
    recent_activity
  ].freeze, T::Array[String])

  sig { returns(String) }
  attr_reader :csv

  sig { returns(String) }
  attr_reader :filename

  sig { params(org: Organization, viewer: User).void }
  def initialize(org:, viewer:)
    @org = T.let(org, Organization)
    @viewer = T.let(viewer, User)
    @csv = T.let(generate_csv, String)
    @filename = T.let("#{@org}-dependencies-#{DateTime.current}.csv", String)
  end

  private

  sig { returns String }
  def generate_csv
    @csv = CSV.generate(encoding: Encoding::UTF_8) do |csv|
      csv << CSV_HEADERS

      explore_loader = SponsorsExploreLoader.new(org: @org, viewer: @viewer)

      sponsorables = T.let(explore_loader.paginated_sponsorables_from_dependencies, T.untyped)

      sponsorables.each do |sponsorable|
        deps_per_sponsorable = []
        sponsorable_id = sponsorable.id
        next unless sponsorable_id

        deps_per_sponsorable = explore_loader.all_dependencies_represented_by_sponsorable(sponsorable_id)
        recent_activity_date = get_recent_activity_date(sponsorable)

        sponsorable.define_singleton_method(:recent_activity_date) { recent_activity_date }

        if deps_per_sponsorable.empty?
          csv << [
            sponsorable.login,
            "",
            recent_activity_date,
          ]
        else
          deps_per_sponsorable.each do |dependency|
            csv << [
              sponsorable.login,
              dependency.name,
              recent_activity_date,
            ]
          end
        end
      end
    end
  end

  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).returns(String) }
  def get_recent_activity_date(sponsorable)
    if sponsorable.type == "User"
      time_range = Contribution::Calendar.time_range_ending_on(Time.zone.now)
      collector = Contribution::Collector.new(
        time_range: time_range,
        user: sponsorable,
        viewer: @org,
      )
      date_range_in_time_zone(collector)&.last&.strftime("%b %-d, %Y")
    elsif sponsorable.type == "Organization"
      sponsorable.repositories.order(pushed_at: :desc).pluck(:pushed_at).first&.strftime("%b %-d, %Y")
    end
  end
end
