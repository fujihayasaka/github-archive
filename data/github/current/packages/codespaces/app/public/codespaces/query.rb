# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Query
    include GitHub::ResilienceMixin

    ACCESSIBLE_CODESPACES = "accessible"

    attr_reader :current_user, :ref, :pull_request, :codespaces_context

    def initialize(
      current_user:,
      repository: nil,
      ref: nil,
      pull_request: nil,
      codespaces_context: nil,
      cap_filter: nil
    )
      @current_user, @repository, @ref, @pull_request, @codespaces_context, @cap_filter =
        current_user, repository, ref, pull_request, codespaces_context, cap_filter
      @repository_policy_promises = {}
    end

    def codespaces(truncated: true)
      raise "Cannot use #codespaces without initializing the query with `cap_filter`" unless @cap_filter

      if defined?(@codespaces)
        if truncated
          return @codespaces.take(MAX_CODESPACES_PAGE_SIZE)
        else
          return @codespaces
        end
      end

      @codespaces = run_codespace_query
        .then { |codespaces| @cap_filter.authorized_resources(codespaces) }

      codespaces(truncated: truncated)
    end

    def codespaces_count(ensure_repo_access: false)
      return @codespaces_count if defined?(@codespaces_count)

      if repository && ensure_repo_access && !repository_policy.can_attempt_create?
        return @codespaces_count = 0
      end

      @codespaces_count = @cap_filter.authorized_resources(codespaces(truncated: false)).count
    end

    # Returns an unpersisted Codespace model that can be referenced for create request parameters.
    def build_codespace
      return @new_codespace if defined?(@new_codespace)

      new_codespace_repository = repository
      new_repository_policy = repository_policy(repository: new_codespace_repository, pull_request: pull_request)
      @new_codespace = current_user.codespaces.build \
        repository: new_codespace_repository,
        ref: ref,
        pull_request: pull_request,
        billable_owner: new_repository_policy.billable_owner
    end

    def show_all_accessible_codespaces?
      codespaces_context == ACCESSIBLE_CODESPACES
    end

    def pull_request_id
      pull_request&.id
    end

    def repository
      @pull_request&.head_repository || @repository
    end

    def repository_policy(repository: self.repository, pull_request: @pull_request)
      prefill_all_accessible_codespaces
      # We're forcibly resolving the repository policy here because either:
      #  1. We already prefilled the repository policy when loading the codespaces,
      #     in which case we're going to synchronously resolve anyways, or
      #  2. We don't have an existing codespace for this (user, repo, PR) in
      #     which case there's no opportunity to batch anyways
      async_repository_policy(repository, pull_request: pull_request).sync
    end

    # Get all accessible codsepaces, ignoring context, repository, or CAP
    # filtering.
    def all_accessible_codespaces
      prefill_all_accessible_codespaces
    end

    def all_accessible_codespaces_for_org(billable_owner = nil)
      return [] if billable_owner.nil? || billable_owner.id.nil?
      all_accessible_codespaces.pluck(:billable_owner_id).find_all { |id| id == billable_owner.id }
    end

    # Is the user currently at their codespace limit?
    def at_limit?(billable_owner = nil)
      user_limit = codespace_limit
      all_accessible_codespaces_count = all_accessible_codespaces.count
      creation_limit = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(billable_owner)

      if !creation_limit.nil?
        all_accessible_codespaces_for_org(billable_owner).count >= creation_limit || all_accessible_codespaces_count >= user_limit
      else
        all_accessible_codespaces_count >= user_limit
      end
    end

    def codespace_limit
      return @codespace_limit if defined?(@codespace_limit)

      @codespace_limit = Codespaces::Policy.codespaces_limit(current_user)
    end

    def all_accessible_running_codespaces
      all_accessible_codespaces.find_all { |c| c.consuming_compute? }
    end

    def default_sku
      return @default_sku if defined?(@default_sku)

      codespace = build_codespace
      @default_sku ||= Codespaces::Skus.default_sku(
        owner: codespace.owner,
        billable_owner: codespace.billable_owner,
        repository: codespace.repository,
        ref: codespace.ref,
        location: Codespaces::GetRegionForUser.call(user: current_user, repository: codespace.repository, client: :dotcom)
      )
    end

    private

    def run_codespace_query
      if show_all_accessible_codespaces?
        all_accessible_codespaces
      elsif repository
        all_accessible_codespaces_for_repo
      else
        []
      end
    end

    def all_accessible_codespaces_for_repo
      all_accessible_codespaces.find_all do |codespace|
        next true if codespace.repository == repository
        next false if codespace.repository.network_id != repository.network_id
        next true if codespace.repository.parent_id == repository.id
        next true if codespace.repository.id == repository.parent_id && repository_policy(repository: codespace.repository).read_only_codespace_required?
        false
      end
    end

    def async_repository_policy(repository, pull_request: nil)
      key = [repository&.id, pull_request&.id]
      context_promise = @repository_policy_promises[key]
      return context_promise if context_promise

      context_promise = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository, pull_request: pull_request)
      @repository_policy_promises[key] = context_promise
    end

    def prefill_all_accessible_codespaces
      return @all_accessible_codespaces if defined?(@all_accessible_codespaces)

      # Explicitly reload because the query cache may have an outdated list of codespaces on this User
      # instance from upstream method calls against it.
      all_codespaces = current_user.codespaces.reload
      # We need T.unsafe here because for $reasons Sorbet doesn't know that `visible_to` (kinda) exists on
      # `all_codespaces`. We are using it like this in other files but chained after `preload` for example which
      # would probably work here too but it feels pretty weird to REQUIRE that ordering in the scope chain just
      # for Sorbet... There were a few other options as well but they all sounded awful...
      @all_accessible_codespaces = T.unsafe(all_codespaces).visible_to(current_user).
        by_recently_used.
        preload([:repository, :owner, :billable_owner])
    end
  end
end
