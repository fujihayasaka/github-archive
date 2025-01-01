# typed: false
# frozen_string_literal: true

module User::ProfilesDependency
  ACV_CONTRIBUTED_REPOSITORIES_LIMIT = 3
  ACV_TOOLTIP = "acv_tooltip"
  NASA_TOOLTIP = "nasa_tooltip"
  BLOCKERS_AND_BLOCKEES_LIMIT = 20

  def starred_repos_count
    return @starred_repos_count if defined?(@starred_repos_count)

    repository_scope = Repository.filter_spam_and_disabled_for(self).public_or_accessible_by(self)

    starred_repository_ids = if self.feature_enabled? :stars_domain_profiles_dependency
      self.starred_repository_ids
    else
      stars.repositories.pluck(:starrable_id)
    end

    @starred_repos_count = starred_repository_ids.each_slice(10_000).sum do |repository_ids|
      repository_scope.where(id: repository_ids).count
    end
  end

  # Public: returns the total number of blockers and blockees for this user
  def block_count
    return @block_count if defined?(@block_count)

    @block_count = blockers_and_blockees.length
  end

  # Public: returns the user metadata record for the user or returns an empty record if none exists
  def metadata
    @_metadata = user_metadata || UserMetadata.new(user: self)
  end

  # IMPORTANT: This method is the gating entry point for showing the Arctic
  # Code Vault contributor badge in the UI, and for running any queries to
  # gather its data. If that ever changes, the `ghost?` check will need to be
  # enforced in the new entry point location(s).
  def can_have_acv_badge?
    # Do not even consider showing (or querying for) the Arctic Code Vault
    # badge when viewing the "ghost" user
    return false if ghost?

    metadata.has_acv_badge
  end

  # Public: returns the number of repositories archived in
  # the Arctic Code Vault that the user has contributed to, filtered down to
  # those that are still public and have not opted out of the GH Archive
  # Program. Use this to quickly get the count without repo information.
  def acv_contribution_count
    return @acv_contribution_count if defined?(@acv_contribution_count)

    @acv_contribution_count = acv_repositories_scope.count
  end

  def all_emails
    @all_emails ||= self.emails.verified.pluck(:email) <<
                    # Include a normalized form of the modern stealth email format to ignore
                    # the user's login, which may or may not have been renamed. See the
                    # repository contribution graph model for prior art.
                    "#{self.id}+username@#{GitHub.stealth_email_host_name}" <<
                    # Include the legacy stealth email format in the hopes that users with
                    # older contributions to the Arctic Code Vault may not have renamed their
                    # user login since then
                    StealthEmail.new(self).legacy_email
  end

  # Public: returns the full unfiltered list of the repository IDs archived in
  # the Arctic Code Vault that the user has contributed to
  def all_acv_repository_ids
    return @all_acv_repository_ids if defined?(@all_acv_repository_ids)

    @all_acv_repository_ids = AcvContributor.group_by_repository(all_emails).pluck(:repository_id)
  end

  # Public: returns a list of most starred repositories archived in the
  # Arctic Code Vault that the user has contributed to that are
  # still publicly available and have not opted out of the GH Archive Program
  def top_acv_repositories(limit: ACV_CONTRIBUTED_REPOSITORIES_LIMIT)
    return @top_acv_repositories if defined?(@top_acv_repositories)
    return [] unless can_have_acv_badge?

    @top_acv_repositories =
      acv_repositories_excluding_blocked_scope
        .order("#{Repository.stargazer_count_column} DESC")
        .first(limit)
  end

  # Public: whether the user has displayable profile highlights
  #
  # Returns a Boolean
  def has_profile_highlights?
    # Do not show or query for profile highlights if viewing the "ghost" user
    return false if ghost?
    profile_highlights && profile_highlights.displayable.exists?
  end

  # Public: the displayable profile highlights for the user
  #
  # Returns an ActiveRecordAssociation
  def displayable_profile_highlights
    return ProfileHighlight.none unless has_profile_highlights?

    profile_highlights.displayable
  end

  # Public: whether the user is eligible to have the Mars 2020 Helicopter
  # Contributor badge
  #
  # Returns a Boolean
  def can_have_nasa_badge?
    nasa_badge = profile_highlights.find_by_highlight_type("nasa_2020")
    return false unless nasa_badge
    nasa_badge.eligible?
  end

  private

  # Private: returns number of users that have blocked this user
  # or have been blocked by this user.
  def blockers_and_blockees
    return @blockers_and_blockees if defined?(@blockers_and_blockees)

    @blockers_and_blockees = ignored_by_users.pluck(:user_id) + ignored_users.pluck(:ignored_id)
  end

  # Private: returns an ActiveRecord scope to query for repositories that are
  # archived in the the Arctic Code Vault which the user has contributed to,
  # filtering out the repositories that are any of the following:
  #   - not public
  #   - opted out of GH Archive Program
  def acv_repositories_scope
    return @acv_repositories_scope if defined?(@acv_repositories_scope)

    # Find the intersection of the user's ACV repository IDs and opted-out
    # repository IDs
    opted_out_repo_ids = Configuration::Entry
      .from("configuration_entries FORCE INDEX (index_configuration_entries_on_target_and_name)")
      .named(Configurable::ArchiveProgramOptOut::KEY)
      .targeting_repository_ids(all_acv_repository_ids)
      .pluck(:target_id)

    # Filter out any repositories that have opted out of the GH Archive Program
    filtered_acv_repo_ids = all_acv_repository_ids - opted_out_repo_ids

    @acv_repositories_scope =
      Repository
        .public_scope
        .where(id: filtered_acv_repo_ids)
  end

  # Private: returns a Boolean indicating if we should skip the
  # repository owner check against this user's list of blockers/blockees
  # We do this for performance reasons: https://github.com/github/profile/issues/347
  def skip_block_query?
    return @skip_block_query if defined?(@skip_block_query)

    @skip_block_query = (block_count == 0) || (block_count > BLOCKERS_AND_BLOCKEES_LIMIT)
  end

  # Private: returns an ActiveRecord scope to query for repositories in the
  # acv_repositories_scope, further filtering out the repositories that are:
  #   - owned by users that have blocked profile user
  #   - owned by users that have been blocked by profile user
  # if their block list is >= BLOCKERS_AND_BLOCKEES_LIMIT
  def acv_repositories_excluding_blocked_scope
    return @acv_repositories_excluding_blocked_scope if defined?(@acv_repositories_excluding_blocked_scope)

    @acv_repositories_excluding_blocked_scope =
      if skip_block_query?
        acv_repositories_scope
      else
        acv_repositories_scope.where("repositories.owner_id NOT IN (?)", blockers_and_blockees)
      end
  end
end
