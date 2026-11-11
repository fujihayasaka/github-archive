# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # RepositoryFilter matches <gh:repository-reference> elements. It performs different types of authorization
  # checks based on properties or methods on a Repository ActiveRecord object.
  #
  # The majority of this filter is built to efficiently batch load database records and should not be modified.
  # To extend this filter, add a new proc to `ASYNC_ACCESS_CHECKS` hash, keyed by the type of authorization check
  # that should be performed. The proc should have the signature `-> (repository, viewer)` and return a Promise that
  # resolves to a boolean indicating whether the viewer has access to the repository content.
  # See existing procs for prior art.
  #
  # To use this authorization check in non-authorization HTML Pipeline filters, include GitHub::Goomba::Reference::Helpers
  # into a filter and call repository_reference_wrapper, e.g.
  #
  # class MyFilter < NodeFilter
  #   include GitHub::Goomba::Reference::Helpers
  #   def call(node)
  #     # find a repository using node content
  #     repo = Repository.find_by(name: node["repo_name"])
  #
  #     # return an authorization wrapper that the Authorization::RepositoryFilter will use to perform a
  #     # "contents" authorization check on the repo, including the content that authorized and unauthorized
  #     # viewers should see
  #     repository_reference_wrapper(repo, check_type: "contents") do |wrapper|
  #       wrapper.authorized { "I can see #{repo.nwo}" }
  #       wrapper.unauthorized { "I cannot see #{node.to_html}" }
  #     end
  #   end
  # end
  class RepositoryFilter < ReferenceFilter
    ELEMENT = "gh:repository-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    def selector
      SELECTOR
    end

    def async_load_resources(nodes)
      return Promise.resolve if nodes.empty?

      ids_to_load = Set.new
      repository_id_to_nodes = Hash.new { |h, k| h[k] = [] }
      nodes.each do |node|
        id = node["repository_id"]&.to_i
        next if id.blank?

        repository_id_to_nodes[id] << node
        next if preloaded_resources["Repository"].has_key?(id)

        ids_to_load << id
      end

      Platform::Loaders::ActiveRecord.load_all(Repository, ids_to_load.to_a, security_violation_behaviour: :allow)
        .then do |loaded_repositories|
          # map all preloaded and newly loaded repositories back to the nodes that referenced them
          (preloaded_resources["Repository"].values + loaded_repositories.compact).each do |repository|
            repository_id_to_nodes[repository.id].each do |node|
              node_repositories[node] = repository
            end
          end
        end
    end

    def async_check_authorization(nodes)
      return Promise.resolve if nodes.empty?

      # first filter all node repositories through CAP checks if a CAP filter is available
      if cap_filter.present?
        repositories = nodes.filter_map { |n| node_repositories[n] }
        authorized_repositories = cap_filter.authorized_resources(repositories)
        nodes = nodes.select { |node| authorized_repositories.include?(node_repositories[node]) }
      end

      # check for access to each repository
      access_checks = nodes.map do |node|
        async_can_access_repository?(node_repositories[node], node["check_type"])
          .then { |accessible| authorized_nodes << node if accessible }
      end

      Promise.all(access_checks)
    end

    private

    def node_repositories
      @node_repositories ||= {}
    end

    # Returns a promise with a value whether the current viewer can see the repository for a known access check
    def async_can_access_repository?(repository, check_key)
      return Promise.resolve(false) if repository.nil?

      # This method is primarily a caching wrapper around access check results. Access check results
      # are cached per repository, per check.

      repository_key = repository.id

      @async_access_cache ||= {}
      if cached_access_check = @async_access_cache.dig(repository_key, check_key)
        return cached_access_check
      end

      access_check = if ASYNC_ACCESS_CHECKS.has_key?(check_key)
        ASYNC_ACCESS_CHECKS[check_key].call(repository, current_user)
      else
        Promise.resolve(false)
      end
      @async_access_cache[repository_key] ||= {}
      @async_access_cache[repository_key][check_key] = access_check
    end

    # The actual access checks that get run for each type of repo check.  Add any new access check types to
    # this hash as a key/value pair like "check_name" => ->(repository, viewer) { }.
    # Access checks return a promise indicating whether the viewer has access to see the repository.
    ASYNC_ACCESS_CHECKS = {
      "contents" => ->(repository, viewer) {
        repository.resources.contents.async_readable_by?(viewer)
      },
      "visible" => ->(repository, viewer) {
        repository.async_readable_by?(viewer)
      },
      "code_scanning" => ->(repository, viewer) {
        next Promise.resolve(false) unless repository.code_scanning_enabled?
        repository.async_code_scanning_readable_by?(viewer)
      },
      "push" => ->(repository, viewer) {
        return Promise.resolve(false) if viewer.nil?
        repository.async_pushable_by?(viewer)
      }
    }
  end
end
