# typed: true
# frozen_string_literal: true

# Module added to Issue model where we track the links to security alerts
module Issue::AlertLinksDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  included do
    T.bind(self, T.class_of(Issue))

    has_many :issue_alert_links
    destroy_dependents_in_background :issue_alert_links
  end

  def security_alert_items_updated?
    return false unless repository = self.repository

    body_changed_after_commit? &&
      repository.issues_alerts_integration_enabled? &&
        (body_result.tracked_alert_anchors.present? || issue_alert_links.count > 0)
  end

  # `reconcile_alerts_from_body` is called when the issue body is changed and
  # the model is save. (called in `after_commit`)
  # It will check if the issue body has any security alerts inside a task-list
  # (it will use the parsed Goomba body. see `GitHub::Goomba::TaskListFilter`
  # and references to `tracked_alert_anchors`).
  # Those links will be saved in the `issue_alert_links` table.
  def reconcile_alerts_from_body
    timer = Timer.start
    current_count = self.issue_alert_links.count

    r = TrackedAlertsReconciliator.new(self).reconcile

    GitHub.dogstats.distribution(
      "issue_alert_link.reconcile.total.dist",
      timer.elapsed_ms,
      tags: [
        "created_alerts:#{r.created.count}",
        "deleted_alerts:#{r.deleted.count}",
        "candidate_alerts:#{r.alert_mentions.count}",
        "tracker_alerts:#{current_count}"
    ])
  end

  class TrackedAlertsReconciliator
    MAX_THROTTLE_RETRIES = 5
    MAX_LINKS = 200

    attr_reader :created, :deleted, :candidate_set

    def initialize(issue)
      @issue = issue
      @author = issue.body_context_user || User.ghost
    end

    # reconcile updates the DB to reflect the set of issue_alert_links in the current issue body.
    def reconcile
      all_created_count = T.let(0, Integer)

      @issue.transaction do
        # lock the issue alert links to prevent concurrent updates while we hold a memory reference to them
        tracked_alert_with_ids = @issue.issue_alert_links.lock("LOCK IN SHARE MODE").pluck(:alert_repository_id, :alert_number, :id).to_set

        # Convert tracked_alert_ids into a hash (alert_repository_id, alert_number) => (id)
        # so we can find the actual ID of the alert link.
        id_hash = tracked_alert_with_ids.each_with_object({}) do |item, hash|
          hash[item[0..1]] = item[2]
        end
        tracked_alerts = id_hash.keys.to_set

        @deleted = (tracked_alerts - alert_mentions).flatten.map { |x| id_hash[x] }

        IssueAlertLink.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          @issue.issue_alert_links.where(id: @deleted).delete_all
        end if @deleted.any?

        # Limit the total number of links: Tracked - Deleted + Created <= MAX
        all_created = alert_mentions - tracked_alerts
        @created = all_created.first(MAX_LINKS - tracked_alerts.length + @deleted.length)
        all_created_count = all_created.count

        @created.each do |(repo, number)|
          IssueAlertLink.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            @issue.issue_alert_links.create!(alert_type: :code_scanning, alert_number: number, actor: @author, alert_repository_id: repo)
          end
        end
      end
      GitHub.dogstats.distribution("alert_links.created", @created.count)
      GitHub.dogstats.distribution("alert_links.deleted", @deleted.count)
      GitHub.dogstats.distribution("alert_links.skipped", (all_created_count - @created.count))

      self
    end

    # alert_mentions returns a set of (repo, number) pairs.
    # Each element is a mention of the alert with the given number
    # for the repo
    def alert_mentions
      return @alert_mentions if defined?(@alert_mentions)
      mentions_by_nwo = @issue.body_result.tracked_alert_anchors&.group_by(&:nwo)
      @alert_mentions = repo_alert_pairs_from_mentions(mentions_by_nwo)
    end

    private

    def repo_alert_pairs_from_mentions(mentions)
      return Set.new if mentions.nil?

      # If no nwo is specified, we are talking about the same repo as the issue
      items = Array(mentions[nil]).map do |m|
        [@issue.repository_id, m.alert_id]
      end

      # Fetch the repo information for all other NWOs
      ::Repository.with_names_with_owners(mentions.keys.compact).select(:id, :name, :owner_login).each do |repo|
        mentions[repo.nwo].each do |m|
          items << [repo.id, m.alert_id]
        end
      end

      items.compact.to_set
    end
  end
end
