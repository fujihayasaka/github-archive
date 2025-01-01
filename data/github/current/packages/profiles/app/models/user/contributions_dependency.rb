# typed: false
# frozen_string_literal: true

module User::ContributionsDependency
  extend ActiveSupport::Concern

  BATCHED_SCOPE_THRESHOLD = 5000

  # Don't show the contributions calendar for bots accounts with a ton of contributions
  LARGE_BOT_ACCOUNTS = Set.new([
    924247,     # KhanBugz
    8518239,    # gitter-badger
    1429315,    # cirosantilli
    16239342,   # pyup-bot
    33116358,   # traviscibot
    10137,      # ghost
  ])

  included do
    has_many :commit_contributions
    has_many :commit_contribution_summaries
    delete_dependents_in_background :commit_contributions
    delete_dependents_in_background :commit_contribution_summaries

    has_many :enterprise_contributions
  end

  def large_bot_account?
    LARGE_BOT_ACCOUNTS.include? id
  end

  # A list of all repository IDs that this user has contributed to in any way.
  # ... well, that is, except the user's own repos.  They don't count.
  #
  # Returns an Array of Repository IDs
  def unfiltered_contributed_repository_ids
    repo_ids = []

    # Repos with issues, PRs, or commits from this user.
    repo_ids << issues.select(:repository_id)

    commit_contribution_repo_ids = ::Collab::Responses::Array.new do
      commit_contributions.select(:repository_id)
    end

    repo_ids << commit_contribution_repo_ids

    repo_ids.flatten.map(&:repository_id).uniq - repository_ids
  end

  # Ranked list of repositories a person has contributed to either by opening
  # an issue, proposing a Pull Request, or pushing a commit.  Each type of contribution
  # is weighted by the values defined in ContributionScorer.
  #
  # Rather than returning straight Repository objects we return a hash whose
  # keys are Repository objects, sorted from most relevant to least, and whose
  # values are Hashes like so:
  #
  #   {
  #     :commits => Integer # of additions and deletions
  #     :pulls   => Integer # of pull requests proposed.
  #     :issues  => Integer # of issues opened.
  #     :score   => Integer "score" - the above three added up plus weighting.
  #   }
  #
  # The :score determines the Repository's ranking in the result.
  #
  # Returns a hash with Repositories as keys and Hashes as values.
  def ranked_contributed_repositories(options = {})
    include_issue_comments = options[:include_issue_comments]
    since = options[:since]

    @ranked_contributed_repositories ||= ranked_contributed_repositories!(include_issue_comments: include_issue_comments,
                                                                                  since: since)
  end

  def ranked_contributed_repositories!(include_issue_comments: false, since: nil)
    scores = {}
    collector = contributions_collector(viewer: self, include_issue_comments: include_issue_comments, since: since)
    oldest_day = collector.first_visible_contribution.try(:occurred_on) || Time.zone.today
    scorer = Contribution::Scorer.new(oldest_day, weighted: true)

    contributions_by_repositories_of(Contribution::CreatedCommit, collector).each do |repo, contributions|
      scores[repo] ||= {}
      scores[repo][:commits] = scorer.score_commits(contributions)
    end

    contributions_by_repositories_of(Contribution::CreatedIssue, collector).each do |repo, contributions|
      scores[repo] ||= {}
      scores[repo][:issues] = scorer.score_issues(contributions)
    end

    contributions_by_repositories_of(Contribution::CreatedPullRequest, collector).each do |repo, contributions|
      scores[repo] ||= {}
      scores[repo][:pulls] = scorer.score_pull_requests(contributions)
    end

    contributions_by_repositories_of(Contribution::CreatedIssueComment, collector).each do |repo, contributions|
      scores[repo] ||= {}
      scores[repo][:issue_comments] = scorer.score_issue_comments(contributions)
    end

    scores.each do |repo, hash|
      hash[:pulls]   ||= 0
      hash[:issues]  ||= 0
      hash[:commits] ||= 0
      hash[:issue_comments] ||= 0
      scores[repo][:score] = hash[:pulls] + hash[:issues] + hash[:commits] + hash[:issue_comments]
    end

    repos_by_owner_id = Hash[scores.map { |repo, _| [repo.owner_id, repo] }]
    ignored_or_ignored_by_ids.each do |user_id|
      next if user_id == id
      if repo = repos_by_owner_id[user_id]
        scores.delete(repo)
      end
    end

    result = {}

    scores.sort_by { |_r, hash| -hash[:score] }.each do |repo, hash|
      result[repo] = hash
    end

    result
  end

  def any_contributions_ever?(viewer: nil)
    return false if self.private_profile_for?(viewer)

    ActiveRecord::Base.connected_to(role: :reading) do
      Repository.where(owner_id: id).exists? ||
      ::Collab::Responses::Boolean.new { CommitContribution.for_user(id).exists? }.value ||
      Issue.for_user(id).exists? ||
      PullRequest.for_user(id).exists? ||
      PullRequestReview.where(user_id: id).exists?
    end
  end

  # Find the repositories the user has contributed to, filtered by an
  # optional viewer access.  Does not include repos the user owns. Does not include repositories
  # whose owners are spammy. The return value is ranked such that recently touched repositories
  # might not make the cut if there were only a couple recent contributions compared
  # to many contributions in the past on other repositories.
  #
  # viewer - Optional User who is viewing the repos - used to enforce authZ
  # limit - Optional Integer of the number of repos requested - defaults to 5
  # exclude_owned - Optional Boolean to exclude repos owned by this user - Defaults to excluding repositories owned by this user
  # repo_type - Optional String of the repository type to filter by - defaults to nil
  # has_issues_enabled - Optional Boolean representing if to filter by issues enabled for the repo - defaults to nil
  #
  # Returns an Array of Repositories
  def repositories_contributed_to(viewer: nil, limit: 5, exclude_owned: true, repo_type: nil, since: nil, has_issues_enabled: nil)
    GitHub.dogstats.distribution_time("contributions", tags: ["action:repositories_contributed_to"]) do
      repos = ::UserRankedRepositories.eager_ranked_for(self, since: since)

      repos.reject! { |repo| repo.owner_id == id } if exclude_owned

      # Filter out repositories with DMCA takedowns or owned by spammy users, unless the viewer is the spammer:
      repos.reject! do |repo|
        viewer_is_anonymous_or_does_not_own_repo = !viewer || repo.owner_id != viewer.id
        (repo.user_hidden? && viewer_is_anonymous_or_does_not_own_repo) || repo.disabled_at.present?
      end

      case repo_type
      when "private"
        repos.reject! { |repo| repo.public? || repo.archived? }
      when "public"
        repos.select! { |repo| repo.public? && !repo.archived? }
      when "template"
        repos.select! { |repo| repo.template? && !repo.archived? }
      when "mirror"
        repos.select! { |repo| repo.mirror? && !repo.archived? }
      when "fork"
        repos.select! { |repo| repo.fork? && !repo.archived? }
      when "source"
        repos.reject! { |repo| repo.mirror? || repo.fork? || repo.archived? }
      when "archived"
        repos.select! { |repo| repo.archived? }
      end

      if has_issues_enabled
        repos.select! { |repo| repo.has_issues? == has_issues_enabled }
      end

      # Make sure the repos are either public or the user can read them
      private_repository_ids = repos.reject { |r| r.public? }.map(&:id)
      associated_private_repository_ids = viewer ? viewer.associated_repository_ids(repository_ids: private_repository_ids).to_set : []
      repos.select! { |repo| repo.public? || associated_private_repository_ids.include?(repo.id) }

      if limit
        repos.first(limit)
      else
        repos
      end
    end
  end

  # Schedule a background job to refresh this user's cached contributions. This
  # is useful for matching commits to a new email address the user just added
  # to their profile.
  #
  # Returns nothing.
  def rebuild_contributions(context: "unknown", only_repos_with_contributions: false)
    repo_ids = if only_repos_with_contributions
      ActiveRecord::Base.connected_to(role: :reading) do
        commit_contributions.distinct.pluck(:repository_id)
      end
    else
      rebuild_contributions_repos
    end

    GitHub.dogstats.distribution("user.rebuild_contributions.repo_count", repo_ids.size, tags: ["context:#{context}"])

    UserContributionsBackfillJob.perform_later(repo_ids, id, context: context)
  end

  def rebuild_contributions_repos
    ActiveRecord::Base.connected_to(role: :reading) do
      repos = repositories.pluck(:id) + member_repositories.pluck(:id)
      org_ids = organizations.pluck(:id)
      # skip the query when the user does not belong to any orgs
      if org_ids.any?
        # Run normal query without batching when the number of orgs is below the threshold
        repos += if org_ids.size <= BATCHED_SCOPE_THRESHOLD
          Repository.where(owner_id: org_ids).active.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
        else
          Repository.batched_scope(:owner_id, values: org_ids, batch_size: BATCHED_SCOPE_THRESHOLD) { |scope| scope.active }.pluck(:id)
        end
      end
      repos.uniq
    end
  end

  # Public: Marks the user as a large-scale contributor.
  # Returns nothing.
  def flag_as_large_scale_contributor!(actor: self)
    Profiles::Kv.store.setnx(large_scale_contributor_key, "1")
    instrument :flag_as_large_scale_contributor, actor: actor
  end

  # Public: Removes the large-scale contributor flag.
  # Returns nothing.
  def remove_large_scale_contributor_flag!(actor: self)
    Profiles::Kv.store.del(large_scale_contributor_key)
    instrument :remove_large_scale_contributor_flag, actor: actor
  end

  # Public: Whether or not the user is flagged as a large-scale contributor.
  # Returns a Boolean.
  def large_scale_contributor?
    Profiles::Kv.store.exists(large_scale_contributor_key).value { false }
  end

  # Public: Flags the provided contribution classes. These contribution classes
  # will be ignored when calculating the user's contributions.
  # Returns nothing.
  def flag_contribution_classes!(contribution_classes, actor: nil)
    return unflag_contribution_classes!(actor: actor) if contribution_classes.empty?

    class_names = contribution_classes.map(&:to_s).join(",")
    Profiles::Kv.store.set(flagged_contribution_classes_key, class_names)
    if actor
      instrument :flag_contribution_classes, actor: actor,
        contribution_classes: class_names
    end
  end

  # Public: Unflags all contribution classes.
  # Returns nothing.
  def unflag_contribution_classes!(actor: nil)
    Profiles::Kv.store.del(flagged_contribution_classes_key)
    instrument(:unflag_contribution_classes, actor: actor) if actor
  end

  # Public: contribution classes that should be ignored when calculating the
  # user's contributions.
  # Returns an Array of Classes.
  def flagged_contribution_classes
    class_names_string = Profiles::Kv.store.get(flagged_contribution_classes_key).value { nil }
    return [] unless class_names_string
    class_names = class_names_string.split(",")
    valid_classes = class_names.inject([]) do |memo, class_name|
      begin
        memo << class_name.constantize
      rescue NameError
        # We found a class name that doesn't exist anymore. Let's ignore it.
        memo
      end
    end

    unless valid_classes.size == class_names.size
      # Let's remove the invalid class names by storing only valid classes.
      flag_contribution_classes!(valid_classes)
    end

    valid_classes
  end

  def contributions_collector(viewer: nil, include_issue_comments: false, since: nil)
    classes = contribution_classes(include_issue_comments: include_issue_comments)
    Contribution::Collector.new(
      user: self,
      time_range: (since || 1.year.ago)..Time.zone.now,
      contribution_classes: classes,
      viewer: viewer,
    )
  end

  def contribution_classes(include_issue_comments: false)
    if include_issue_comments
      Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS + [Contribution::CreatedIssueComment]
    else
      Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS
    end
  end

  private

  def large_scale_contributor_key
    "user.large_scale_contributor.#{id}"
  end

  def flagged_contribution_classes_key
    "user.flagged_contribution_classes.#{id}"
  end

  def contributions_by_repositories_of(contribution_class, contributions_collector)
    contributions = contributions_collector.visible_contributions_of(contribution_class)
    contributions.group_by(&:repository)
  end
end
