# typed: strict
# frozen_string_literal: true

# Given a link to a resource, tries to create a reference object for it.
class Copilot::ChatLinkItem
  include GitHub::Memoizer
  include Copilot::Chat::ReferenceBuildersDependency

  sig { returns(T.nilable(String)) }
  attr_reader :item_url
  sig { returns(User) }
  attr_reader :user

  sig { params(item_url: T.nilable(String), user: User).void }
  def initialize(item_url, user)
    @item_url = T.let(item_url&.delete_prefix("/"), T.nilable(String))
    @user = user
    raise ArgumentError, "user cannot be nil" if user.nil?
  end

  sig { returns(T::Array[String]) }
  memoize def item_url_parts
    return [] unless item_url
    uri = URI.parse(T.must(item_url)) rescue nil
    uri&.path&.split("/", 5) || []
  end

  # the day sorbet supports recursive type aliases is the day we can remove this disable
  sig { returns T.nilable(T.any(Issue, Discussion, PullRequest, Repository, TreeEntry, ::Figma::File, T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
  memoize def item
    return unless item_url

    return figma_file if figma_url?

    owner, repo, type, id, rest = item_url_parts
    return unless owner && repo

    case type
    when nil, ""
      # no readable_by? check here because we verify that repository is readable by the user
      return repository
    when "issues"
      return repository unless id # return repo for index pages
      issue = repository&.issues&.find_by(number: id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return issue&.readable_by?(user) ? issue : nil
    when "pull"
      return repository unless id
      pull_request = repository&.issues&.find_by(number: id)&.pull_request # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return pull_request&.readable_by?(user) ? pull_request : nil
    when "discussions"
      return repository unless id
      discussion = repository&.discussions&.find_by(number: id)
      return discussion&.readable_by?(user) ? discussion : nil
    when "blob", "tree"
      # blob and tree URLs do not have valid index pages
      return nil unless id && rest
      combined_path = "#{id}/#{rest}"
      # no readable_by? check here because we verify that repository is readable by the user
      return tree_entry(combined_path)
    when "actions"
      return repository unless id
      route = T.cast(Rails.application.routes.recognize_path(item_url), T::Hash[Symbol, String])
      if route[:controller] == "actions/job" && route[:action] == "index"
        # no readable_by? check here because we verify that repository is readable by the user and the rest just comes from the URL
        return job(route)
      end
    end

    # If we reach here, we don't have a valid item, log so we can consider adding support for it
    route = T.cast(Rails.application.routes.recognize_path(item_url), T::Hash[Symbol, String])
    GlobalInstrumenter.instrument(
      "analytics.event",
      category: "copilot_chat_link_item",
      action: "unsupported_item",
      label: "controller:#{route[:controller]};action:#{route[:action]}",
    )
    nil
  end

  sig { returns(T.nilable(Reference)) }
  memoize def reference
    i = item
    return nil unless i

    case i
    when Repository
      repository_reference(i)
    when Issue
      issue_reference(i)
    when Discussion
      discussion_reference(i)
    when PullRequest
      pull_request_reference(i)
    when TreeEntry
      tree_entry_reference(i, T.must(@sha))
    when ::Figma::File
      figma_reference(i)
    when Hash
      i
    end
  end

  # returns an object you can call target_for_conditional_access on
  sig { returns T.nilable(T.any(Discussion, Issue, PullRequest, Repository, ::Figma::File)) }
  memoize def conditional_access_item
    i = item
    if i.is_a?(TreeEntry) || i.is_a?(Hash)
      # For TreeEntry, we return the repository as the item for conditional access
      repository
    else
      i
    end
  end

  private

  sig { returns T.nilable(Repository) }
  memoize def repository
    owner, repo = item_url_parts
    r = Repository.with_name_with_owner("#{owner}/#{repo}") if owner && repo # rubocop:disable GitHub/DoNotAllowLogin
    return nil unless r&.readable_by?(user)
    r
  end

  sig { params(combined_path: String).returns(T.nilable(TreeEntry)) }
  def tree_entry(combined_path)
    repo = repository
    return nil unless repo
    ref_sha_path_extractor = GitHub::RefShaPathExtractor.new(repo)
    branch, path = ref_sha_path_extractor.call(combined_path)
    @sha = T.let(branch.present? ? repo.ref_to_sha(branch) : repo.default_oid, T.nilable(String))
    repo.tree_entry(@sha, path) rescue nil if path.present?
  end

  sig { params(route: T::Hash[Symbol, String]).returns(T.nilable(Reference)) }
  def job(route)
    repo = repository
    return nil unless repo
    job_reference(repo, route[:job_id].to_s)
  end

  sig { returns T.nilable(::Figma::File) }
  memoize def figma_file
    return unless figma_url?

    GitHub.figma_client.get_file(T.must(item_url))
  rescue ::Figma::APIError => e
    Rails.logger.error("Failed to fetch Figma file: #{e}")
    nil
  end

  ALLOWED_FIGMA_HOSTS = ["figma.com", "www.figma.com"].freeze

  sig { returns(T.nilable(T::Boolean)) }
  memoize def figma_url?
    return false unless item_url

    uri = URI.parse(T.must(item_url))
    ALLOWED_FIGMA_HOSTS.include?(uri.host)
  end
end
