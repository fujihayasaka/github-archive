# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  class ProjectFilter < ReferenceFilter
    ELEMENT = "gh:project-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    def selector
      SELECTOR
    end

    def async_load_resources(nodes)
      return Promise.resolve if nodes.empty?

      ids_to_load = Set.new
      project_id_to_nodes = Hash.new { |h, k| h[k] = [] }
      nodes.each do |node|
        id = node["project_id"]&.to_i
        next if id.blank?

        project_id_to_nodes[id] << node
        next if preloaded_resources["Project"].has_key?(id)

        ids_to_load << id
      end

      Platform::Loaders::ActiveRecord.load_all(MemexProject, ids_to_load.to_a, security_violation_behaviour: :allow)
        .then do |loaded_projects|
          # map all preloaded and newly loaded projects back to the nodes that referenced them
          (preloaded_resources["Project"].values + loaded_projects.compact).each do |project|
            project_id_to_nodes[project.id].each do |node|
              node_projects[node] = project
            end
          end
        end
    end

    def async_check_authorization(nodes)
      return Promise.resolve if nodes.empty?

      if cap_filter.present?
        projects = nodes.filter_map { |n| node_projects[n] }
        authorized_resources = cap_filter.authorized_resources(projects)
        nodes = nodes.select { |node| authorized_resources.include?(node_projects[node]) }
      end

      # check for access to each project
      access_checks = nodes.map do |node|
        return unless project = node_projects[node]

        project.async_readable_by?(current_user).then { |accessible| authorized_nodes << node if accessible }
      end

      Promise.all(access_checks)
    end

    # When the viewer doesn't have access to see a project, remove any
    # references to that project from the result object
    def access_denied(node)
      return unless node
      project = node_projects[node]

      result[:projects].try(:delete_if) { |p| p.id == project.id }
    end

    private

    def node_projects
      @node_projects ||= {}
    end
  end
end
