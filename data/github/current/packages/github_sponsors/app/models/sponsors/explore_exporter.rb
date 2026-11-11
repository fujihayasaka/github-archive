# typed: true
# frozen_string_literal: true

module Sponsors
  class ExploreExporter
    SPONSORABLE_NAME_FIELD = "Maintainer name"
    TOTAL_DEPENDENCIES_MAINTAINED_FIELD = "Total dependencies maintained"
    GOAL_PROGRESS_FIELD = "Goal progress"
    GOAL_DESCRIPTION_FIELD = "Goal description"
    TOTAL_SPONSORS_FIELD = "Total sponsors"
    TOTAL_ORG_SPONSORS_FIELD = "Total organization sponsors"
    HEADERS = [
      BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD,
      SPONSORABLE_NAME_FIELD,
      TOTAL_DEPENDENCIES_MAINTAINED_FIELD,
      GOAL_PROGRESS_FIELD,
      GOAL_DESCRIPTION_FIELD,
      TOTAL_SPONSORS_FIELD,
      TOTAL_ORG_SPONSORS_FIELD,
      BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD,
    ].freeze
    CSV_INJECTION_CHARS = ["=", "+", "-", "@", ";", "%=00"]

    include GitHub::Memoizer

    # explore_loader - a SponsorsExploreLoader for the first page of results
    # filter_set - a SponsorsExploreFilterSet starting at the first page of the desired results
    # viewer - the User who is authenticated and requesting the export
    def initialize(explore_loader:, filter_set:, viewer:)
      @explore_loader = explore_loader
      @filter_set = filter_set
      @viewer = viewer
    end

    def filename
      prefix = "github-explore-sponsors"
      whose_deps = "for-#{account_login}"
      parts = [prefix, whose_deps]
      parts << "in-" + ecosystems.join("-").downcase if ecosystems.any?
      parts << "w-indirect-deps" unless direct_dependencies_only?
      parts << formatted_current_date_for(viewer)
      parts.join("-") + ".csv"
    end

    def to_csv
      CSV.generate do |csv|
        csv << HEADERS

        sponsorables.each do |sponsorable|
          # Keep in same order as the header row's columns so the values in each column match how we label them:
          csv << HEADERS.map { |header| value_for(sponsorable, header: header) }
        end
      end
    end

    private

    attr_reader :explore_loader, :filter_set, :viewer

    delegate :ecosystems, :direct_dependencies_only?, to: :filter_set

    delegate :account_login, :total_associated_dependencies, :total_sponsors,
      :total_org_sponsors, :sponsoring?, to: :explore_loader

    memoize def sponsorables
      list = explore_loader.sponsorables_from_dependencies
      GitHub::PrefillAssociations.prefill_associations(list, [:profile, { sponsors_listing: :active_goal }])
      list
    end

    def value_for(sponsorable, header:)
      case header
      when BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD
        sponsorable.login
      when SPONSORABLE_NAME_FIELD
        name_for(sponsorable)
      when TOTAL_DEPENDENCIES_MAINTAINED_FIELD
        total_associated_dependencies(sponsorable)
      when GOAL_PROGRESS_FIELD
        goal_progress_for(sponsorable)
      when GOAL_DESCRIPTION_FIELD
        goal_description_for(sponsorable)
      when TOTAL_SPONSORS_FIELD
        total_sponsors(sponsorable.id)
      when TOTAL_ORG_SPONSORS_FIELD
        total_org_sponsors(sponsorable.id)
      when BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD
        nil
      end
    end

    def name_for(sponsorable)
      profile_name = sponsorable.safe_profile_name
      # Leave column blank when it's the same as the sponsorable's username
      return nil if profile_name == sponsorable.login
      sanitize_name(profile_name)
    end

    def goal_progress_for(sponsorable)
      active_goal = active_goal_by_sponsorable_id[sponsorable.id]
      return unless active_goal

      active_goal.percent_complete.to_i
    end

    def goal_description_for(sponsorable)
      active_goal = active_goal_by_sponsorable_id[sponsorable.id]
      active_goal&.title
    end

    memoize def active_goal_by_sponsorable_id
      sponsorables.each_with_object({}) do |sponsorable, hash|
        hash[sponsorable.id] = sponsorable.sponsors_listing.active_goal
      end
    end

    def formatted_current_date_for(viewer)
      now = Time.now
      now = now.in_time_zone(viewer.time_zone_name) if viewer&.time_zone_name
      now.strftime("%Y-%m-%d")
    end

    def sanitize_name(name)
      sanitized_name = name
      CSV_INJECTION_CHARS.each do |offending_char|
        sanitized_name = sanitized_name.delete(offending_char)
      end
      sanitized_name
    end
  end
end
