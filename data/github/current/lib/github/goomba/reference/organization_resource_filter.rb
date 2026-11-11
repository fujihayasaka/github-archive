# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # OrganizationResourceFilter matches <gh:organization-resource-reference> elements. It performs authorization
  # checks on ActiveRecord objects which require an `organization` association to be loaded before
  # authorization can be checked, e.g. `Team` records.
  #
  # The majority of this filter is built to efficiently batch load database records and should not be modified.
  # To extend this filter, add a new proc to `ASYNC_ACCESS_CHECKS` hash, keyed by the resource type string name.
  # The proc should have the signature `-> (resource, viewer)` and return a Promise that
  # resolves to a boolean indicating whether the viewer has access to the resource.  See existing procs for prior art.
  #
  # To use this authorization check in non-authorization HTML Pipeline filters, include GitHub::Goomba::Reference::Helpers
  # into a filter and call organization_resource_reference_wrapper, e.g.
  #
  # class MyFilter < NodeFilter
  #   include GitHub::Goomba::Reference::Helpers
  #   def call(node)
  #     # find a resource that requires an organization association to be loaded, based on node data
  #     team = Team.find_by(slug: node["team_slug"])
  #
  #     # return an authorization wrapper that the Authorization::OrganizationResourceFilter will use to perform an
  #     # authorization check on the team, including the content that authorized and unauthorized viewers should see
  #     organization_resource_reference_wrapper(team) do |wrapper|
  #       wrapper.authorized { "I'm an employee and can see #{team.slug}" }
  #       wrapper.unauthorized { "I'm not an employee and cannot see this team" }
  #     end
  #   end
  # end
  class OrganizationResourceFilter < ReferenceFilter
    ELEMENT = "gh:organization-resource-reference".freeze
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

      # batch load all resources' organizations together, to minimize the number of org lookups needed
      Promise.all(resource_loaders)
        .then { |resource_type_lists| resource_type_lists.flatten }
        .then { |resources|  async_load_resource_organizations(resources) }
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
        async_can_access_resource?(node_resources[node])
          .then { |accessible| authorized_nodes << node if accessible }
      end

      Promise.all(access_checks)
    end

    # When the viewer doesn't have access to see a resource, remove any references to that resource
    # from the result object
    def access_denied(node)
      return unless node

      resource = node_resources[node]
      case resource
      when Team
        result[:mentioned_teams].try(:delete_if) { |team| team.id == resource.id }
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

      # return the list of preloaded resources + newly loaded resources
      Platform::Loaders::ActiveRecord.load_all(resource_type.constantize, resource_ids_to_load.to_a)
        .then { |resources| preloaded_type_resources.to_a + resources.compact }
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

    # Batch loads all needed organization associations for the provided resources.
    # Returns nothing.
    def async_load_resource_organizations(resources)
      return if resources.empty?

      ids_to_load = Set.new
      resources.each do |r|
        next if r.association(:organization).loaded?

        # don't reload organizations which have already been loaded
        next if preloaded_resources["Organization"].has_key?(r.organization_id)

        ids_to_load << r.organization_id
      end

      Platform::Loaders::ActiveRecord.load_all(Organization, ids_to_load.to_a)
        .then do |organizations|
          organizations.compact.each { |org| preloaded_resources["Organization"][org.id] ||= org }

          resources.each do |r|
            next if r.association(:organization).loaded?
            r.organization = preloaded_resources["Organization"][r.organization_id]
          end
        end
    end

    # Returns a promise with a value whether the current viewer can see the provided resource.
    def async_can_access_resource?(resource)
      return Promise.resolve(false) if resource.nil?

      # cache the access check result per resource
      resource_key = "#{resource.class.name}/#{resource.id}"

      @async_access_cache ||= {}
      if cached_access_check = @async_access_cache[resource_key]
        return cached_access_check
      end

      access_check = if ASYNC_ACCESS_CHECKS.has_key?(resource.class.name)
        ASYNC_ACCESS_CHECKS[resource.class.name].call(resource, current_user)
      else
        Promise.resolve(false)
      end
      @async_access_cache[resource_key] = access_check
    end

    # The actual access checks that get run for each type of resource.  Add any new resource type access checks to
    # this hash as a key/value pair like "ResourceClassName" => ->(resource, viewer) { }.
    # Access checks return a promise indicating whether the viewer has access to see the resource.
    ASYNC_ACCESS_CHECKS = {
      "Team" => ->(team, viewer) {
        next Promise.resolve(false) if team.organization.nil?
        team.async_visible_to?(viewer)
      }
    }.freeze
  end
end
