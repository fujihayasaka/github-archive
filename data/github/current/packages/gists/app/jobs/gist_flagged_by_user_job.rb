# typed: false
# frozen_string_literal: true

# Enqueued from Gist when a user clicks "Report as abuse" button on a gist.
#
# Initially we're just going to re-check the Gist content via the
# normal gist spam checker.
class GistFlaggedByUserJob < ApplicationJob
  queue_as :spam
  retry_on_dirty_exit

  def perform(gist_id, user_id)
    gist = Gist.find_by_id(gist_id.to_i)
    user = User.find_by_id(user_id.to_i)
    Failbot.push(
      "gh.job.name": self.class.name,
      "gh.gist.owner.id": gist&.user&.id,
      "gh.gist.id": gist_id,
      "gh.user.id": user&.id,
    )

    fail "gist #{gist_id} doesn't exist" if gist.nil?

    # Staff reports get their own reporting, below
    unless user && user.site_admin?
      # Note the button push stat, even if we can't go any further below.
      GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:gist", "flag_type:by_user"]
    end

    # Not much to do right now about anonymous gists
    return unless gist.user

    # If they're already spammy, then our work here is done.
    return if gist.user.spammy?

    # If User is reporting himself, let's just move silently on
    return if user_id == gist.user_id

    # If a Hubber hit the button, just mark the gist spammy and log it.
    if user && user.site_admin?
      reason = "Gist #{gist.id} flagged via 'Report as abuse' button"
      with_write do
        gist.user.mark_as_spammy(reason: reason, actor: user)
      end
      GitHub.dogstats.increment "spam.flagged", tags: ["spam_target:gist", "flag_type:by_staff"]

      # If a Hubber is manually nailing a spammer's gist, toss his IP
      # on the naughty list for a while.
      with_write do
        Spam::ip_denylist(gist.user.last_ip)
      end
    end

    # Queue the reported user for review. If it's spammy, there are
    # probably more where it crawled from.
    GitHub::SpamChecker.notify("Gist %d (%s) reported for spam by %s" % [gist.id, gist.url, user.login])
    GlobalInstrumenter.instrument(
      "add_account_to_spamurai_queue",
      {
        account_global_relay_id: gist.user.global_relay_id,
        additional_context: "RESQUE",
        origin: :RESQUE,
        queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
      },
    )
  end
end
