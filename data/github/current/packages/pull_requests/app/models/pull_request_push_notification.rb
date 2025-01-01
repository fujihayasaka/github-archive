# typed: true
# frozen_string_literal: true

class PullRequestPushNotification
  include GitHub::UserContent

  COMPOUND_REF_ID_REGEX = /\APull#(?<pull_id>\d+)Before#(?<before>[0-9a-f]{40})After#(?<after>[0-9a-f]{40})PushedAt#(?<pushed_at>\d+)Pusher#(?<pusher_id>\d+)\z/
  attr_reader :pull_request, :ref_update, :pusher, :pushed_at

  # Repository must come from the pull request as opposed to the push since
  # it acts as the notification list. In the case of PRs from forks, we don't
  # to notify the users subscribed to the fork but the repo the pull request
  # belongs to.
  delegate :repository, :issue, to: :pull_request

  # Tell Newsies where to get the information it needs.
  alias_method :user, :pusher
  alias_method :entity, :repository
  alias_method :notifications_list, :repository
  alias_method :notifications_thread, :issue
  alias_method :notifications_author, :user

  def async_entity
    Promise.resolve(entity)
  end

  # Public: Instantiates a PullRequestPushNotification given a compound key
  # which includes the PullRequest and Push record IDs. Called by the
  # deliver-notifications job to find the notification instance.
  #
  # compound_id - Required compound ID String.
  #
  # Returns a PullRequestPushNotification or nil if not found.
  def self.find_by_id(compound_id)  # rubocop:disable GitHub/FindByDef
    return unless match = COMPOUND_REF_ID_REGEX.match(compound_id.to_s)

    pull = PullRequest.find_by(id: match[:pull_id].to_i)
    return unless pull

    new(pull_request: pull, before: match[:before], after: match[:after], ref: pull.head_ref, pushed_at: Time.at(match[:pushed_at].to_i), pusher: User.find_by(id: match[:pusher_id].to_i))
  end

  def initialize(pull_request:, before: nil, after: nil, ref: nil, pushed_at: nil, pusher: nil)
    @pull_request = pull_request
    @ref_update = Repositories::RefUpdate.new(before: before, after: after, ref: "refs/heads/#{ref}", repository: repository, pusher: pusher)
    @pusher = pusher
    @pushed_at = pushed_at
  end

  def id
    "Pull##{ pull_request.id }Before##{ ref_update.before }After##{ ref_update.after }PushedAt##{ pushed_at.to_i }Pusher##{ ref_update.pusher.id }"
  end

  def permalink
    "#{ pull_request.permalink }/files/#{ ref_update.before }..#{ ref_update.after}"
  end

  def user_id
    user.try(:id)
  end

  def message_id
    "<#{repository.name_with_display_owner}/pull/#{issue.number}/before/#{ref_update.before}/after/#{ref_update.after}@#{GitHub.urls.host_name}>"
  end

  def commits
    return [] if ref_update.large_push?
    pull_comparison.commits
  end

  def diff_entries
    return [] if ref_update.large_push?
    pull_comparison.diffs.entries
  end

  def body
    login = "@#{user.display_login}" if user.present?
    "#{login || "Somebody"} pushed #{commits.length} #{"commit".pluralize(commits.size)}."
  end

  def new_record?
    false
  end

  def non_fast_forward?
    ref_update.non_fast_forward?
  end

  def created_at
    pushed_at
  end

  private

  def pull_comparison
    return @pull_comparison if defined?(@pull_comparison)

    merge_base_oid = pull_request.compare_repository.best_merge_base(pull_request.base_sha, ref_update.after)

    @pull_comparison = PullRequest::Comparison.find \
      pull: pull_request,
      start_commit_oid: ref_update.before,
      end_commit_oid: ref_update.after,
      base_commit_oid: merge_base_oid
  end
end
