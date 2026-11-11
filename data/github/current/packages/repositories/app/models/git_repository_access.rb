# typed: true
# frozen_string_literal: true

# This class handles Repository and Gist access disabling and enabling.
#
# To use this class your model needs the following r/w attributes:
# - disabled_at
# - disabled_by
# - disabling_reason
# - disabling_detail
# - dmca_takedown
# - country_blocks (Necessary for GitRepositoryBlock)

class GitRepositoryAccess
  class Error < StandardError; end
  class RepoDisableError < StandardError; end
  class RepoNetworkDisableError < StandardError; end

  # Valid reasons for disabling a git repository.
  REASONS = if GitHub.enterprise?
    %w(admin size)
  else
    %w(broken dmca sensitive_data size tos trademark private_information)
  end
  TAKEDOWN_URL_FORMAT = %r{
      https://github.com/github/dmca/blob/master/  # Must be in the DMCA repo
      20\d\d/                                      # Year directory
      (20\d\d-\d\d-\d\d|\d\d/20\d\d-\d\d-\d\d)     # Date format and optional month folder
    }x

  attr_reader :git_repository
  sig { returns(String) }
  attr_reader :type

  def initialize(git_repository)
    raise Error, "invalid type: #{@type}" unless %w[gist repository].include?(@type)

    @git_repository = git_repository
    @block = GitRepositoryBlock.new(git_repository, @type)
  end

  # Disable git, web, and api access to this repository and its forks.
  #
  # The disable operation is not performed in a transaction,
  # so (if errors occur) it's possible for the network to be only
  # partially disabled after this method returns
  #
  # reason - Short string identifying the reason for disabling access.
  #          Must be one of REASONS.
  # user   - The User responsible for removing access. Staff members only.
  #
  # Returns list of successfully disabled repos and list of repos we
  # failed to disable.
  def disable(reason, user,
    instructions: nil,
    dmca_takedown: nil,
    disabling_detail: nil,
    email_template: nil,
    notify_fork_owners: true,
    tos_reason: nil,
    content_formats: nil,
    source: nil,
    dsa_required: true
  )
    is_dmca = reason == "dmca"

    if disabled? && !is_dmca
      raise Error, "#{git_repo_stat_key} already disabled"
    end

    if !REASONS.include?(reason)
      raise Error, "invalid reason: #{reason.inspect}"
    end

    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(user)

    disabled_at = Time.now

    attributes = {
      disabled_at: disabled_at,
      disabled_by: user,
      disabling_reason: reason,
      disabling_detail: disabling_detail,
    }

    # Make sure we delete the parent repo last. This way users will be
    # able to retry the operation if some forks fail to be deleted.
    ordered_repos = git_repositories.select { |repo| repo != git_repository }
    ordered_repos << git_repository

    successes = []
    failures = []
    errors = []

    ordered_repos.each do |repo|
      # Don't sent repeat notifications to fork owners when disable operation is retried (e.g. from partial failures)
      next if repo.disabling_reason == reason

      # Don't disable the parent unless all forks were successfully disabled.
      is_parent = repo == git_repository
      if is_parent && failures.any?
        failures << repo
        break
      end

      begin
        git_repository.transaction do
          DisabledAccessReason.transaction do
            repo.update!(attributes)
            if is_dmca
              DisabledAccessReason.new do |reason|
                reason.dmca_takedown_url = dmca_takedown
                reason.flagged_item_id = repo.id
                reason.flagged_item_type = type
                reason.disabled_by = user
                reason.disabled_at = T.cast(disabled_at, T.untyped)
              end.save!
            end
          end
        end

        successes << repo
        if repo.is_a?(Repository) && FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
          Repositories.domain.reload(repo)
        else
          repo.reload
        end

        payload = auditing_actor
          .merge(
            git_repo_stat_key => repo,
            :user => repo.owner,
            :reason => reason,
            :details => disabling_detail,
          )
          .compact
        GitHub.instrument("staff.disable_#{git_repo_stat_key}", payload)

        # type will be either a repo or a gist, use that value here to get the string
        repo_or_gist_key = type.to_sym

        GlobalInstrumenter.instrument "#{type}.disabled", {
          repo_or_gist_key => repo,
          :actor => user,
          :disabled_at => Time.now,
          :reason => reason,
          :details => disabling_detail,
          :dmca_takedown_url => dmca_takedown
        }

        if dsa_required || is_dmca
          GlobalInstrumenter.instrument "#{type}.disabled_dsa", {
            repo_or_gist_key => repo,
            :actor => user,
            :tos_reason => is_dmca ? :TRADEMARK : tos_reason,
            :content_formats => is_dmca ? [:TEXT] : content_formats,
            :source => is_dmca ? :USER_REPORT : source
          }
        end

        if is_parent || notify_fork_owners
          deliver_disabled_notice(instructions, repo: repo, email_template: email_template)
        end
      rescue => e # rubocop:todo Lint/RescueException
        Failbot.report(RepoDisableError.new(e.message))
        failures << repo
        errors << e
      end
    end

    if failures.any?
      Failbot.report(RepoNetworkDisableError.new, {
        "gh.repo.parent.id": git_repository.id,
        "gh.repo.disable.success_ids": successes.map(&:id),
        "gh.repo.disable.failure_ids": failures.map(&:id),
      })
    end

    if git_repository.is_a?(Repository) && FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(git_repository)
    else
      git_repository.reload
    end

    # Only do this stuff if the _parent_ repo was successfully disabled.
    if failures.blank?
      GitHub.dogstats.increment("repo.disable", tags: ["disable_reason:#{reason}"])
      instrument_disable_for_blackbird_search
      notify_sponsors_team_if_matchable_sponsorable
    end

    { successes: successes, failures: failures, errors: errors }
  end

  # Re-enable access to this git_repository via all protocols.
  #
  # user - The staff User responsible for restored access.
  #
  # Returns nothing.
  def enable(user)
    if !disabled?
      raise Error, "#{git_repo_stat_key} not disabled"
    end

    attributes = {
      disabled_at: nil,
      disabled_by: nil,
      disabling_reason: nil,
    }

    old_disable_reason = disabling_reason
    begin
      git_repository.transaction do
        git_repositories.each do |repo|
          repo.update!(attributes)
          repo.access.disabled_access_record.try(:delete)
        end
      end
      GitHub.dogstats.increment("repo.enable", tags: ["disable_reason:#{old_disable_reason}"])
    rescue ActiveRecord::RecordInvalid => e
      Failbot.report Error.new(e.message)
      return false
    end

    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(user)
    git_repositories.each do |repo|
      GitHub.instrument "staff.enable_#{git_repo_stat_key}", auditing_actor.merge(
        git_repo_stat_key => repo,
        :disable_reason => old_disable_reason,
        :user => repo.owner)

      repo_or_gist_key = type.to_sym
      GlobalInstrumenter.instrument "#{type}.enabled", {
        repo_or_gist_key => repo,
        :actor => user,
        :enabled_at => Time.now,
      }
    end

    if git_repository.is_a?(Repository) && FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(git_repository)
    else
      git_repository.reload
    end

    instrument_enable_for_blackbird_search

    true
  end

  # Is this git repository disabled? Disabled access means no interaction possible
  # at all through any protocol.
  def disabled?
    !disabled_at.nil? || !git_repository.active?
  end

  def enabled?
    !disabled?
  end

  # When this git repository was disabled.
  def disabled_at
    git_repository.disabled_at
  end

  # The User that requested this repository to be disabled.
  def disabler
    if disabled?
      User.find(git_repository.disabled_by)
    end
  end

  # Short string identifying the reason for disabling access to this repository.
  def disabling_reason
    if disabled?
      git_repository.disabling_reason
    end
  end

  # Detailed reason for disabling, often including tags for support routing
  def disabling_detail
    if disabled?
      git_repository.disabling_detail
    end
  end

  # Disable access to a repo that has a DMCA takedown against it. This applies
  #
  # user - staff user record
  # url  - URL of the public takedown notice, currently placed on github/dmca
  #
  # Returns true when successful, false-ish otherwise.
  def dmca_takedown(user, url)
    if url !~ TAKEDOWN_URL_FORMAT
      git_repository.errors.add(:base, "Invalid takedown notice URL")
      return
    end

    DisableRepositoryAccessJob.perform_later(git_repository, "dmca", user, dmca_takedown: url)

    true
  end

  def mark_broken_git_repository
    git_repository.update!(
      disabled_at: Time.now,
      disabling_reason: "broken",
    )

    GitHub.instrument "staff.disable_#{git_repo_stat_key}", git_repo_stat_key => git_repository,
      :user => git_repository.owner, :reason => "broken"

    if git_repository.is_a?(Repository) && FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(git_repository)
    else
      git_repository.reload
    end

    # TODO: maybe email the user to let them know something broke?
    # deliver_disabled_notice(nil)
  end

  # Whether this repository was disabled due to a DCMA takedown.
  def dmca?
    disabled? && disabling_reason == "dmca"
  end

  # URL of the DMCA takedown notice for this repository.
  def dmca_url
    disabled_access_record.try(:dmca_takedown_url)
  end

  def blocked_countries
    @block.blocked_countries
  end

  def country_block?(country)
    @block.country_block?(country)
  end

  def country_block(user, block, url, reason, tos_reason: nil, content_formats: nil, source: nil)
    @block.country_block(user, block, url, reason, tos_reason:, content_formats:, source:)
  end

  def country_block_url(country)
    @block.country_block_url(country)
  end

  def remove_country_block(user, block)
    @block.remove_country_block(user, block)
  end

  def country_block_setup?(block)
    @block.country_block_setup?(block)
  end

  def country_blocks
    @block.country_blocks
  end

  def deliver_disabled_notices(instructions, repos, reason:, email_template: nil)
    tags = ["disable_reason:#{reason}"]
    repos.each do |repo|
      begin
        deliver_disabled_notice(instructions, repo: repo, email_template: email_template)
        GitHub.dogstats.increment("repo.disable_notice", tags: tags)
      rescue => e # rubocop:todo Lint/RescueException
        Failbot.report(e)
        GitHub.dogstats.increment("repo.disable_notice_error", tags: tags)
      end
    end
  end

  # Notify (email) the git_repository owner that it has been disabled.
  def deliver_disabled_notice(instructions, email_template: nil, repo: git_repository)
    return if type == "gist"
    return if repo.deleted?

    case repo.access.disabling_reason
    when "dmca"
      RepositoryMailer.dmca_takedown_notice(repo, repo.access.dmca_url).deliver_later
    when "size"
      RepositoryMailer.size_disabled_notice(repo, instructions, template: email_template).deliver_later
    when "tos"
      RepositoryMailer.tos_disabled_notice(repo, instructions, template: email_template).deliver_later
    when "private_information"
      RepositoryMailer.private_information_disabled_notice(repo, instructions, template: email_template).deliver_later
    when "trademark"
      RepositoryMailer.trademark_disabled_notice(repo, instructions, template: email_template).deliver_later
    when "admin"
      RepositoryMailer.admin_disabled_notice(repo, instructions).deliver_later
    else
      raise Error, "attempt to deliver notice for invalid reason: #{repo.disabling_reason}"
    end
  end

  # Public: Whether this git_repository was disabled due to abuse of resources
  def abusive?
    disabling_reason == "size"
  end

  # Public: Whether this git_repository was disabled due to TOS violations
  def tos_violation?
    disabling_reason == "tos"
  end

  def sensitive_data_violation?
    disabling_reason == "sensitive_data"
  end

  def private_information_violation?
    disabling_reason == "private_information"
  end

  def trademark_violation?
    disabling_reason == "trademark"
  end

  # Public: Whether this git_repository was disabled by an admin.
  def disabled_by_admin?
    disabling_reason == "admin"
  end

  # Public: Whether this git_repository is broken
  def broken?
    async_broken?.sync
  end

  def async_broken?
    return Promise.resolve(true) if disabling_reason == "broken"
    return Promise.resolve(false) unless git_repository.respond_to?(:async_network_broken?)

    git_repository.async_network_broken?
  end

  def tos_violation_review_link
    disabling_confidence_tag = case disabling_detail
    when /tos-disabled-amber/
      "tos-vra"
    when /tos-disabled-red/
      "tos-vrr"
    else
      "tos-vru"
    end

    subject = "TOS Review: #{git_repository.name_with_owner}".truncate(50)
    GitHub.contact_support_url(subject: subject, tags: disabling_confidence_tag)
  end

  # Public: Fetches the corresponding disabld access record (if any)
  def disabled_access_record
    if git_repository.respond_to?(:disabled_access_reason)
      git_repository.disabled_access_reason
    else
      DisabledAccessReason.find_by(flagged_item_id: git_repository.id, flagged_item_type: type)
    end
  end

  private

  # Returns the first four of the git repository's class
  # as a symbol.  For example:
  # Repository -> :repo
  # Gist -> :gist
  def git_repo_stat_key
    git_repo_full_name.first(4).to_sym
  end

  # Returns the git repository's class as a lower
  # case string.
  def git_repo_full_name
    git_repository.class.name.downcase
  end

  # Git repositories affected by access change. Includes the whole network when the
  # git repository is the root and just the one when it's a fork.
  def git_repositories
    if git_repository.fork?
      [git_repository]
    else
      if type == "gist"
        [git_repository].concat git_repository.forks.includes(:user)
      else
        # include soft-deleted repos in case they get restored later
        git_repository.network.active_and_deleted_repositories.includes(:owner)
      end
    end
  end

  # emit DISABLED event for Blackbird code search indexing on the supplied repo
  def instrument_disable_for_blackbird_search
    return unless type == "repository" || type == "archived_repository"

    payload = {
      change: :DISABLED,
      repository: git_repository,
      owner_name: git_repository.owner.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{git_repository.default_branch}",
    }

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:disabled"])
  end

  # emit RESTORED event for Blackbird code search indexing on the supplied repo
  def instrument_enable_for_blackbird_search
    return unless type == "repository" || type == "archived_repository"

    payload = {
      change: :RESTORED,
      repository: git_repository,
      owner_name: git_repository.owner.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{git_repository.default_branch}",
    }

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:restored"])
  end

  # Private: Notify the Sponsors team if a repository is being ToS disabled, if
  #          the owner has a published Sponsors listing that is matchable.
  def notify_sponsors_team_if_matchable_sponsorable
    return unless GitHub.sponsors_enabled?
    return unless tos_violation?
    return if type != "repository"

    owner = git_repository.owner
    listing = owner.sponsors_listing
    return if listing.blank?
    return unless listing.approved?
    return unless listing.matchable?

    url = UrlHelpers.stafftools_sponsors_member_path(
      owner.display_login,
      host: GitHub.admin_host_name,
    )
    message = "Matchable sponsorable's repository was disabled!" \
              " #{git_repository.name_with_owner} - [View in Sponsors stafftools](#{url})"

    GitHub::Chatterbox.client.say!("#sponsors-activity-alerts", message)
  end
end
