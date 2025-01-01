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
    return unless GitHub.flipper[:feature_management_curated_segments_job].enabled?

    staff_users = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_staff_users.duration") do
      fetch_staff_users
    end
    send_hydro_message("staff_users", staff_users)

    staff_repos = GitHub.dogstats.time("#{STATS_PREFIX}.fetch_staff_repos.duration") do
      fetch_staff_repos
    end
    send_hydro_message("staff_repos", staff_repos)
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

  sig { params(segment_name: String, actors: T::Hash[String, T::Boolean]).void }
  def send_hydro_message(segment_name, actors)
    stats_tags = ["segment_name:#{segment_name}"]

    # Guard against accidentally over writing curated segments with empty actors
    # Please update or remove in case we ever have segments that can be empty
    if actors.empty?
      GitHub.dogstats.increment("#{STATS_PREFIX}.empty_actors", tags: stats_tags)
      return
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
