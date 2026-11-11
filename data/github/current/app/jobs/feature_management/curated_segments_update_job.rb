# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class FeatureManagement::CuratedSegmentsUpdateJob < ApplicationJob
  STATS_PREFIX = "gh.feature_management.curated_segments_update_job"

  queue_as :curated_segments_update
  schedule interval: 1.hour, condition: -> { !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?) }
  retry_on_dirty_exit

  sig { void }
  def perform
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    staff_users = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_staff_users.duration") do
      fetch_staff_users
    end
    send_hydro_message("staff_users", staff_users)

    staff_repos = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_staff_repos.duration") do
      fetch_staff_repos
    end
    send_hydro_message("staff_repos", staff_repos)

    github_stars_members = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_github_stars_members.duration") do
      fetch_github_stars_members
    end
    send_hydro_message("github_stars_members", github_stars_members)

    microsoft_team_members = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_microsoft_team_members.duration") do
      fetch_microsoft_team_members
    end

    microsoft_team_segments = split_microsoft_team_members_into_segments(microsoft_team_members)
    microsoft_team_segments.each do |segment_name, actors|
      send_hydro_message(segment_name, actors, false)
    end

    shopify_members = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_shopify_members.duration") do
      fetch_shopify_members
    end
    send_hydro_message("shopify_members", shopify_members)
  end

  private

  sig { returns(T::Hash[String, T::Boolean]) }
  def fetch_staff_users
    org = Organization.find_by_login("github")
    teams_ids = org.teams.where(slug: %w[employees interns]).pluck(:id)
    team_member_ids = Ability.where(
      subject_id: teams_ids,
      subject_type: "Team",
      actor_type: "User",
      priority: Ability.priorities[:direct]
    ).distinct.pluck(:actor_id)
    team_member_ids.each_with_object({}) { |user_id, actors| actors["User:#{user_id}"] = true }
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  def fetch_staff_repos
    repos = Repository.select(:id).where(owner_login: "github").where.not(public: true)
    repos.each_with_object({}) { |repo, actors| actors[repo.vexi_id] = true }
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  def fetch_github_stars_members
    org = Organization.find_by_login("GitHub-Stars")
    teams_ids = org.teams.where(slug: %w[stars]).pluck(:id)
    team_member_ids = Ability.where(
      subject_id: teams_ids,
      subject_type: "Team",
      actor_type: "User",
      priority: Ability.priorities[:direct]
    ).distinct.pluck(:actor_id)
    team_member_ids.each_with_object({}) { |user_id, actors| actors["User:#{user_id}"] = true }
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  def fetch_microsoft_team_members
    org = Organization.find_by_login("microsoft")
    teams_ids = org.teams.where(slug: %w[everyone]).pluck(:id)
    team_member_ids = Ability.where(
      subject_id: teams_ids,
      subject_type: "Team",
      actor_type: "User",
      priority: Ability.priorities[:direct]
    ).distinct.pluck(:actor_id)
    team_member_ids.each_with_object({}) { |user_id, actors| actors["User:#{user_id}"] = true }
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  def fetch_shopify_members
    org = Organization.find_by_login("shopify")
    org_member_ids = Ability.where(
      subject_id: org.id,
      subject_type: "Organization",
      actor_type: "User"
    ).distinct.pluck(:actor_id)
    org_member_ids.each_with_object({}) { |user_id, actors| actors["User:#{user_id}"] = true }
  end

  # This logic is intended to split the range of user ids into 9 segments, with a 10th reserved for future use.
  # - Because there is a maximum segment actor count of 9,999, we're using a set of breakpoint ids to allocate the
  #   users to the segments.
  # - The breakpoints were chosen based on the current member distribution of the microsoft everyone team such that
  #   the first 8 segments would contain roughly 5000 users each with the ninth containing the remainder.
  # - This will allow users to be added and removed without moving between segments causing any associated feature
  #   flag checks to potentially flap off and on.
  sig { params(members: T::Hash[String, T::Boolean]).returns(T::Hash[String, T::Hash[String, T::Boolean]]) }
  def split_microsoft_team_members_into_segments(members)
    # Create empty segments with zero-padded names
    segments = (1..10).each_with_object({}) do |i, hash|
      hash["microsoft_team_members_%02d" % i] = {}
    end

    # Define breakpoints for segment allocation based on user ids
    breakpoints = [
      [5300771, "microsoft_team_members_01"],
      [12544861, "microsoft_team_members_02"],
      [22666651, "microsoft_team_members_03"],
      [38957715, "microsoft_team_members_04"],
      [58849004, "microsoft_team_members_05"],
      [91211819, "microsoft_team_members_06"],
      [124709897, "microsoft_team_members_07"],
      [199155687, "microsoft_team_members_08"]
    ]

    members.each do |user_id, value|
      # Extract the numeric ID from the user_id string (format: "User:1234")
      numeric_id = user_id.split(":")[1].to_i

      # Determine segment based on breakpoints
      segment_name = breakpoints.find { |limit, _| numeric_id < limit }&.last || "microsoft_team_members_09"
      segments[segment_name][user_id] = value
    end

    segments
  end

  sig { params(segment_name: String, actors: T::Hash[String, T::Boolean], prevent_empty: T::Boolean).void }
  def send_hydro_message(segment_name, actors, prevent_empty = true)
    stats_tags = ["segment_name:#{segment_name}"]

    # Guard against accidentally over writing curated segments with empty actors
    if actors.empty?
      GitHub.dogstats.increment("#{STATS_PREFIX}.empty_actors", tags: stats_tags)
      return if prevent_empty
    end

    GitHub.dogstats.count("#{STATS_PREFIX}.actor_count", actors.size, tags: stats_tags)
    Hydro::PublishRetrier.publish(
      {
        name: segment_name,
        actors: actors,
      },
      key: segment_name,
      partition_key: segment_name,
      schema: "featureflags.data.v0.Segment",
      topic: "featureflags.vexi.v0.CuratedSegment",
      publisher: GitHub.hydro_publisher,
    )
  end
end
