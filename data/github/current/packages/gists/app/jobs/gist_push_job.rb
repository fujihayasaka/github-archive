# typed: true
# frozen_string_literal: true

# Enqueued immediately by the git post-receive hook after a user pushes
# to a gist repository. All refs pushed are provided in the payload.
#
#   path      - The full path to the repository that was pushed to on disk.
#   pusher    - The String name of the user who performed the push; or, the
#               "<user>/<repo>" when push was performed over ssh with deploy
#               key authentication.
#   refs      - An Array of [ref, before, after] tuples, one for each
#               ref that was pushed.
#   pushed_at - The time when the push completed.
#
class GistPushJob < ApplicationJob
  queue_as :gist_push
  retry_on_dirty_exit

  # Do the dirt.
  def perform(path, pusher, refs, pushed_at, _push_options = nil, _oauth_access_id = nil)
    gist = Gist.with_path(path)
    Failbot.push(
      "gh.job.name": self.class.name,
      "gh.gist.anonymous": gist && gist.anonymous?,
      "gh.gist.owner.id": gist&.user_id,
      "gh.gist.id": gist&.id,
      "gh.gist.path": path,
      "git.ref_updates": refs.inspect,
      "gh.actor.name": pusher,
    )
    pushed_at ||= Time.now

    fail "gist doesn't exist" if gist.nil?

    with_write do
      gist.increment_push_counts
      gist.update_pushed_at pushed_at

      gist.async_backup(opts: { pushed_at: pushed_at })
      gist.synchronize_search_index

      update_disk_usage(gist)
    end

    publish_gist_push_event(gist, pusher, refs, pushed_at)
  end

  # Update the current disk usage for this gist.
  #
  # We're using the `enqueue_once_per_interval` helper from ApplicationJob to
  # prevent recalculating the disk usage too many times during many frequent
  # pushes. We will only calculate disk usage _once_ for all the pushes
  # after an hour has passed.
  def update_disk_usage(gist)
    GistDiskUsageJob.enqueue_once_per_interval(args: [gist.id], interval: 60 * 60)
  end

  def publish_gist_push_event(gist, pusher, refs, pushed_at)
    return unless refs.any?
    updates = refs.map do |(ref, before, after)|
      {
        ref_name: ref&.dup&.force_encoding(Encoding::UTF_8),
        previous_ref_oid: before,
        current_ref_oid: after,
      }
    end

    message = {
      actor: Hydro::EntitySerializer.user(User.find_by_login(pusher)),
      owner: Hydro::EntitySerializer.user(gist.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      gist: Hydro::EntitySerializer.gist(gist),
      ref_updates: Array.wrap(updates),
      feature_flags: gist.feature_flags_on_gists,
      pushed_at: pushed_at,
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "github.v1.GistPush",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 }
    )
  end
end
