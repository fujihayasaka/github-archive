# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # RepositoryResourceFilter matches <gh:repository-resource-reference> elements. It performs authorization
  # checks on ActiveRecord objects which require a `repository` association to be loaded before
  # authorization can be checked, e.g. `Issue` or `Discussion` records.
  # It also validates that the content returned from the cache is not stale.
  #
  # The majority of this filter is built to efficiently batch load database records and should not be modified.
  # To extend this filter, add a new proc to `ASYNC_ACCESS_CHECKS` hash, keyed by the resource type string name.
  # The proc should have the signature `-> (resource, viewer, current_repository)` and return a Promise that
  # resolves to a boolean indicating whether the viewer has access to the resource.  See existing procs for prior art.
  #
  # To use this authorization check in non-authorization HTML Pipeline filters, include GitHub::Goomba::Reference::Helpers
  # into a filter and call repository_resource_reference_wrapper, e.g.
  #
  # class MyFilter < NodeFilter
  #   include GitHub::Goomba::Reference::Helpers
  #   def call(node)
  #     # find a resource that requires a repository association to be loaded, using node data
  #     issue = Issue.find_by(number: node["issue_number"])
  #
  #     # return an authorization wrapper that the Authorization::RepositoryResourceFilter will use to perform an
  #     # authorization check on the issue, including the content that authorized and unauthorized viewers should see
  #     repository_resource_reference_wrapper(issue) do |wrapper|
  #       wrapper.authorized { "I can see issue ##{issue.number}" }
  #       wrapper.unauthorized { "I'm cannot see this issue" }
  #     end
  #   end
  # end
  class RepositoryResourceFilter < ReferenceFilter
    ELEMENT = "gh:repository-resource-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    def selector
      SELECTOR
    end

    def async_load_resources(nodes)
      return Promise.resolve if nodes.empty?

      # batch load resources by type
      resource_loaders = nodes
        .group_by { |node| node["resource_type"] }
        .map do |type, nodes|
          async_batch_load_resource_type(type, nodes).then do |resources|
            # populate a map linking node->resource for fast resource lookup
            # during authorization
            populate_node_resource_map(nodes, resources)
            resources
          end
        end

      # batch load all resources' repositories together, to minimize the number of repository lookups needed
      Promise.all(resource_loaders)
        .then { |resource_type_lists| resource_type_lists.flatten }
        .then { |resources|  prefill_resource_repositories(resources) }
    end

    def async_check_authorization(nodes)
      return Promise.resolve if nodes.empty?

      # first filter all node resources through CAP checks if a CAP filter is available
      if cap_filter.present?
        resources = nodes.filter_map { |n| node_resources[n] }
        authorized_resources = cap_filter.authorized_resources(resources)
        nodes = nodes.select { |node| authorized_resources.include?(node_resources[node]) }
      end

      access_checks = nodes.map do |node|
        async_can_access_resource?(node_resources[node], node["check_type"]&.to_sym)
          .then { |accessible| authorized_nodes << node if accessible }
      end

      Promise.all(access_checks)
    end

    def async_check_for_stale_content(nodes)
      return Promise.resolve if nodes.empty?

      nodes.each do |node|
        updated_at = node_resources[node].try(:updated_at)
        if updated_at && node.attributes["resource_signature"] != updated_at.to_s
          raise StaleReferenceError
        end
      end

      Promise.resolve
    end

    # When the viewer doesn't have access to see a repository, remove any references to the mentioned
    # issue/discussion from the result object
    def access_denied(node)
      return unless node

      resource = node_resources[node]
      case resource
      when Issue
        result[:issues].try(:delete_if) { |ref| ref.issue.id == resource.id }
      when Discussion
        result[:discussions].try(:delete_if) { |ref| ref.discussion.id == resource.id }
      end
    end

    private

    def node_resources
      @node_resources ||= {}
    end

    # Returns a promise that resolves to all of the available resources for the resource type and
    # provided nodes.
    def async_batch_load_resource_type(resource_type, nodes)
      # if we can't perform an access check on the resource type, don't attempt to load
      # resources of that type
      return Promise.resolve([]) unless ASYNC_ACCESS_CHECKS.has_key?(resource_type)

      # map the nodes to resources that have been preloaded and resource ids that need to be loaded
      preloaded_type_resources = Set.new
      resource_ids_to_load = Set.new
      nodes.each do |node|
        resource_id = node["resource_id"].to_i
        if resource = preloaded_resources.dig(resource_type, resource_id)
          preloaded_type_resources << resource
        else
          resource_ids_to_load << resource_id
        end
      end

      # return the preloaded resources if there is nothing else to load
      return Promise.resolve(preloaded_type_resources.to_a) if resource_ids_to_load.empty?

      # return the list of preloaded resources + newly loaded resources
      Platform::Loaders::ActiveRecord.load_all(resource_type.constantize, resource_ids_to_load.to_a)
        .then { |resources| preloaded_type_resources.to_a + resources.compact }
        .rescue do |exception|
          if OPTIONAL_RESOURCES.include?(resource_type) &&
            GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST.any? { |klass| exception.is_a?(klass) }
            Failbot.report(exception)
            []
          else
            raise exception
          end
        end
    end

    # Populate the node_resource map which links a node to its corresponding resource for easy lookup
    # Returns nothing.
    def populate_node_resource_map(nodes, resources)
      indexed_resources = resources.index_by(&:id)
      nodes.each do |node|
        index = node["resource_id"].to_i
        resource = indexed_resources[index]
        next unless resource

        node_resources[node] = resource
      end
    end

    # Prefills all needed repositories associations for the provided resources.
    # Returns nothing.
    def prefill_resource_repositories(resources)
      return if resources.empty?

      ids_to_load = Set.new
      resources.each do |r|
        next if r.association(:repository).loaded?

        # don't reload repositories which have already been loaded
        next if preloaded_resources["Repository"].has_key?(r.repository_id)

        ids_to_load << r.repository_id
      end

      return Promise.resolve if ids_to_load.empty?

      Platform::Loaders::ActiveRecord.load_all(Repository, ids_to_load.to_a, security_violation_behaviour: :allow)
        .then do |repositories|
          repositories.compact.each { |repository| preloaded_resources["Repository"][repository.id] ||= repository }

          resources.each do |r|
            next if r.association(:repository).loaded?
            r.repository = preloaded_resources["Repository"][r.repository_id]
          end
        end
    end

    # Returns a promise with a value whether the current viewer can see the provided resource.
    def async_can_access_resource?(resource, check_type)
      return Promise.resolve(false) if resource.nil? || resource.repository.nil?

      # This method is primarily a caching wrapper around access check results. The finest grain
      # of permissions that we currently support is checked per resource type per repository.
      # To keep performance costs to a minimum we assume that access to a resource in a repository
      # means that a viewer can access all resources of the same type in the same repository

      repository_key = resource.repository.id
      resource_key = resource.class.name

      # pull request mentions will be treated as issue mentions by the issue mention filter.
      # they are separate resource types with separate access checks, which we account for here
      if resource.is_a?(Issue) && resource.pull_request_id.present?
        resource_key = PullRequest.name
      end

      # User assets uploaded to code files require separate access checks to account for forks
      if resource.is_a?(UserAsset) && resource.upload_container_type == "RepositoryBlob"
        resource_key = "BlobAsset"
      end

      @async_access_cache ||= {}
      if cached_access_check = @async_access_cache.dig(repository_key, resource_key)
        return cached_access_check
      end

      access_check = if ASYNC_ACCESS_CHECKS.has_key?(resource_key)
        ASYNC_ACCESS_CHECKS[resource_key].call(resource, current_user, repository, check_type)
      else
        Promise.resolve(false)
      end
      @async_access_cache[repository_key] ||= {}
      @async_access_cache[repository_key][resource_key] = access_check
    end

    # Resource types declared as optional will not raise database exceptions during batch loading.
    # Instead we will treat database failures as these resource not existing.
    OPTIONAL_RESOURCES = ["RepositoryVulnerabilityAlert"].freeze

    # The actual access checks that get run for each type of resource.  Add any new resource type access checks to
    # this hash as a key/value pair like "ResourceClassName" => ->(resource, viewer, current_repository) { }.
    # Access checks return a promise indicating whether the viewer has access to see the resource.
    ASYNC_ACCESS_CHECKS = {
      "Issue" => ->(issue, viewer, current_repository, check_type) {
        if !issue.repository.has_issues
          # the issue's repository doesn't currently have issues enabled - no access
          next Promise.resolve(false)
        elsif check_type == :read && issue.repository.id == current_repository&.id && !viewer&.can_have_granular_permissions?
          # the viewer doesn't have granular permissions, and the issue is in the current repository
          # so the viewer has access to see the issue
          next Promise.resolve(true)
        end

        case check_type
        when :read
          issue.async_readable_by?(viewer)
        when :write
          issue.async_editable_by?(viewer)
        else
          next Promise.resolve(false)
        end
      },
      "PullRequest" => ->(pull, viewer, current_repository, check_type) {
        if check_type == :read && pull.repository.id == current_repository&.id && !viewer&.can_have_granular_permissions?
          # the viewer doesn't have granular permissions, and the PR is in the current repository
          # so the viewer has access to see the PR
          next Promise.resolve(true)
        end

        case check_type
        when :read
          pull.async_readable_by?(viewer)
        when :write
          pull.async_editable_by?(viewer)
        else
          next Promise.resolve(false)
        end
      },
      "Discussion" => ->(discussion, viewer, current_repository, _check_type) {
        if !discussion.repository.discussions_active?
          # the discussion's repository doesn't currently have discussions enabled - no access
          next Promise.resolve(false)
        elsif viewer&.can_have_granular_permissions?
          # TODO: Discussions will end up supporting granular repo resource checks
          # but we're not sure exactly what to do about that yet.
          # https://github.com/github/github/pull/140918#issuecomment-621492555
          next Promise.resolve(false)
        elsif discussion.repository.id == current_repository&.id
          # the viewer doesn't have granular permissions, and the discussion is in the current repository
          # so the viewer has access to see the discussion
          next Promise.resolve(true)
        end

        discussion.async_readable_by?(viewer)
      },
      "RepositoryAdvisory" => -> (repository_advisory, viewer, current_repository, _check_type) {
        if repository_advisory.repository.id == current_repository&.id
          next Promise.resolve(true)
        elsif !repository_advisory.published?
          next Promise.resolve(false)
        elsif repository_advisory.repository.nil?
          next Promise.resolve(false)
        end

        repository_advisory.repository.async_readable_by?(viewer)
      },
      "UserAsset" => ->(asset, viewer, current_repository, _check_type) {
        next Promise.resolve(true) if asset.repository_id == current_repository&.id

        asset.repository.async_readable_by?(viewer)
      },
      "BlobAsset" => ->(asset, viewer, current_repository, _check_type) {
        next Promise.resolve(true) if asset.repository_id == current_repository&.id
        next Promise.resolve(true) if !current_repository&.parent.nil? && asset.repository_id == current_repository&.parent.id

        asset.repository.async_readable_by?(viewer)
      },
      "RepositoryVulnerabilityAlert" => ->(alert, viewer, _current_repository, _check_type) {
        next Promise.resolve(false) unless alert.repository.vulnerability_alerts_enabled?
        alert.repository.vulnerability_alerts_visible_to?(viewer)
      },
    }.freeze
  end
end
