# typed: true
# frozen_string_literal: true

class ProfilePinner
  REPO_LIMIT_ORG = 2000
  REPO_LIMIT_USER = 1000

  # Public: Removes the given items from user's pinned list on their profile.
  #
  # items_to_unpin - one or more Repositories or Gists to unpin from the user's profile
  # user - a User or Organization
  # viewer - the User who is doing the unpinning
  #
  # Returns nothing.
  def self.unpin(*items_to_unpin, user:, viewer:, internal_view: false)
    GitHub.logger.info(
      "code.namespaces" => "ProfilePinner",
      "code.function" => "unpin",
      "gh.profiles.internal_view" => internal_view,
      "gh.profiles.viewer_id" => viewer.id,
      "gh.profiles.actor_id" => user.id,
      "gh.profiles.items_to_unpin_ids" => items_to_unpin.map(&:id),
    )
    items = ActiveRecord::Base.connected_to(role: :reading) { user.pinned_items(viewer: viewer, internal_view: internal_view) }
    pinner = ProfilePinner.new(user: user, viewer: viewer, items: items, viewing_as_member: internal_view)
    pinner.async_unpin(items_to_unpin).sync
  end

  def self.pin(*items_to_pin, user:, viewer:, internal_view: false)
    GitHub.logger.info(
      "code.namespace" => "ProfilePinner",
      "code.function" => "pin",
      "gh.profiles.internal_view" => internal_view,
      "gh.profiles.viewer.id" => viewer.id,
      "gh.profiles.actor.id" => user.id,
      "gh.profiles.items_to_pin_ids" => items_to_pin.map(&:id),
    )
    items = ActiveRecord::Base.connected_to(role: :reading) { user.pinned_items(viewer: viewer, internal_view: internal_view) }
    items = items + items_to_pin
    pinner = ProfilePinner.new(user: user, viewer: viewer, items: items, viewing_as_member: internal_view)
    pinner.async_pin.sync
  end

  attr_reader :user, :viewer, :items

  # viewing_as_member - Defaults to false. Only applicable when viewing an organization profile;
  # set to true when the viewer is viewing the members-only view of an organization, and
  # allows private/internal repositories to also be pinned
  def initialize(user:, viewer:, items: nil, viewing_as_member: false)
    @user = user
    @viewer = viewer
    @items = items || []
    @viewing_as_member = viewing_as_member
  end

  # Public: Returns a Promise that resolves to a list of repositories and gists the user is allowed
  # to pin.
  #
  # types - list of pinnable item types to include, defaults to including all possible types;
  #         valid values include "Repository" and "Gist"
  #
  # Returns a Promise resolving to an Array of Repositories and Gists.
  def async_pinnable_items(types: ProfilePin.pinned_item_types.keys, repo_limit: REPO_LIMIT_USER)
    if user.organization?
      async_organization_pinnable_items(types: types, repo_limit: REPO_LIMIT_ORG)
    elsif user.user?
      Promise.resolve(user_pinnable_items(types: types, repo_limit: repo_limit))
    else # bots can't pin repositories
      Promise.resolve([])
    end
  end

  # Public: Get a Promise returning a list of repos and gists that can be pinned for this user.
  #
  # types - list of pinnable item types to include, defaults to including all possible types;
  #         valid values include "Repository" and "Gist"
  #
  # Returns a Promise resolving to an Array of Repositories and Gists.
  def async_sorted_pinnable_items(types: ProfilePin.pinned_item_types.keys)
    async_pinnable_items(types: types).then do |pinnable_items|
      # Preload stargazer counts for Gists so they can be loaded in a single batch. For other
      # pinnable items, we can fall back to loading them as-needed since they use counter
      # caches.
      stargazer_counts = Hash.new { |counts, item| counts[item] = item.stargazer_count }
      pinnable_gists = pinnable_items.select do |item|
        item.is_a?(Gist)
      end
      if pinnable_gists.any?
        loader = Platform::Loaders::GistStargazerCount.new
        result = loader.fetch(pinnable_gists.map(&:id))
        pinnable_gists.each do |gist|
          stargazer_counts[gist] = result[gist.id]
        end
      end

      user.async_pinned_items(viewer: viewer, internal_view: @viewing_as_member).then do |already_pinned_items|
        total_pins = already_pinned_items.count
        has_pins = total_pins > 0

        # give preference to repos/gists owned by user, then fall back to number of stars
        if user.user?
          pinnable_items.sort_by do |item|
            sort_order = if item.is_a?(Repository)
              is_my_repo = item.owner_id == user.id
              [
                is_my_repo ? 0 : 1,
                -stargazer_counts[item],
                item.name_with_owner.downcase,
              ]
            else # Gist
              is_my_gist = item.user_id == user.id
              [
                is_my_gist ? 0 : 1,
                -stargazer_counts[item],
                item.name.downcase,
              ]
            end

            if has_pins
              position = already_pinned_items.index(item) || total_pins
              sort_order = [position] + sort_order
            end

            sort_order
          end
        # already pre-sorted by number of stars in #async_organization_pinnable_items
        elsif user.organization?
          already_pinned_items | pinnable_items
        # bots can't pin repos
        else
          []
        end
      end
    end
  end

  def async_unpin(items_to_unpin)
    items_to_unpin.each do |item|
      items.delete(item)
    end

    async_pin # deletes pins from list, resorts, and saves.
  end

  # Public: Pin a list of repositories and gists to a user's profile.
  #
  # types - list of item types to allow being pinned, defaults to including all possible types;
  #         valid values include "Repository" and "Gist"
  #
  # Returns nothing.
  def async_pin(types: ProfilePin.pinned_item_types.keys)
    profile = user.find_or_create_profile

    async_items_to_pin(types: types).then do |items_to_pin|
      profile.pin_items(items_to_pin, internal_view: @viewing_as_member)
    end
  end

  private

  def async_organization_pinnable_items(types:, repo_limit: REPO_LIMIT_ORG)
    if types.include?("Repository")
      if @viewing_as_member
        Promise.resolve(user.repositories.most_starred.limit(repo_limit).filter_spam_and_disabled_for(viewer))
      else
        Promise.resolve(user.public_repositories.most_starred.limit(repo_limit).filter_spam_and_disabled_for(viewer))
      end
    else
      Promise.resolve([])
    end
  end

  def async_organization_all_pinnable_items(types:)
    if types.include?("Repository")
      if @viewing_as_member
        Promise.resolve(user.repositories.where(id: items.map(&:id)).filter_spam_and_disabled_for(viewer))
      else
        Promise.resolve(user.public_repositories.where(id: items.map(&:id)).filter_spam_and_disabled_for(viewer))
      end
    else
      Promise.resolve([])
    end
  end

  def user_pinnable_items(types:, repo_limit: REPO_LIMIT_USER)
    pins = user.pinned_items(viewer: viewer, types: types)
    my_repos = other_repos = []

    if types.include?("Repository")
      my_repos = public_repositories_owned_or_contributed_to(repo_limit: repo_limit)
      other_repos = other_repositories_with_commits
    end

    gists = if types.include?("Gist")
      user.gists.are_public.filter_spam_and_disabled_for(viewer)
    else
      []
    end

    (pins + my_repos + gists + other_repos).uniq
  end

  def async_items_to_pin(types:)
    if user.organization?
      async_organization_all_pinnable_items(types: types).then do |items_to_pin|
        items & items_to_pin
      end
    else
      async_pinnable_items(types: types).then do |pinnable_items|
        items & pinnable_items
      end
    end
  end

  # Private: Returns a list of the user's owned, active, public repositories as
  # well as public repositories to which they have contributed recently.
  def public_repositories_owned_or_contributed_to(repo_limit: REPO_LIMIT_USER)
    ActiveRecord::Base.connected_to(role: :reading) do
      # Should include repositories contributed to in the last year:
      contributed_repo_ids = user.contributions_collector(viewer: viewer).visible_repository_ids
      Repository.active.public_scope.
        where("repositories.owner_id = ? OR repositories.id IN (?)",
              user.id, contributed_repo_ids).
        filter_spam_and_disabled_for(viewer).
        order("pushed_at DESC").limit(repo_limit)
    end
  end

  # Private: Get other repositories the user has committed to that may not be included in
  # what the contributions collector finds because the commits were made too long ago.
  #
  # Returns an Array or a Repository relation.
  def other_repositories_with_commits
    return [] if user.large_bot_account? || user.large_scale_contributor?

    ActiveRecord::Base.connected_to(role: :reading) do
      repo_ids = CommitContributions.domain.contributed_repo_ids(user: user, prior_to: 1.year.ago).take(REPO_LIMIT_USER)
      validator = CommitContribution::RepositoryValidator.new(user, repository_ids: repo_ids)
      valid_repo_ids = validator.valid_repository_ids

      Repository.active.public_scope.where(id: valid_repo_ids).
        filter_spam_and_disabled_for(viewer)
    end
  end
end
