# typed: true
# frozen_string_literal: true

module PackageDependencies
  class View < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :parsed_query, :raw_query, :enabled_orgs, :selected_org_ids, :cap_filter,
      :unauthorized_organizations, :dependency_graph_timed_out, :dependency_graph_unavailable

    def stringify_query(query)
      new_query = Search::Queries::PackageDependenciesQuery.stringify(query)
      new_query.present? ? new_query : nil
    end

    def matches_qualifier?(component, qualifier)
      component.is_a?(Array) && qualifier == component.first
    end

    def contains_qualifier?(qualifier_name, qualifier_value = nil)
      parsed_query.any? do |component|
        next false unless matches_qualifier?(component, qualifier_name)
        qualifier_value.nil? || qualifier_value.to_s.casecmp?(component.second)
      end
    end

    def build_query(qualifier:, value: nil, remove: false, replace: false)
      query = parsed_query.select do |component|
        next true unless matches_qualifier?(component, qualifier)
        next false if replace && qualifier == component.first
        value != nil && !value.to_s.casecmp?(component.second)
      end

      query << [qualifier, value] if value && !remove

      stringify_query(query)
    end

    def build_query_with_only_qualifier(qualifier)
      query = parsed_query.select do |component|
        matches_qualifier?(component, qualifier)
      end
      stringify_query(query)
    end

    def package_index_path(package_name, package_version, package_manager)
      query = parsed_query.dup
      query << [:name, package_name]
      query << [:version, package_version]
      query << [:ecosystem, package_manager.downcase]
      urls.packages_dashboard_path(query: stringify_query(query))
    end

    def dependency_graph_error?
      dependency_graph_timed_out || dependency_graph_unavailable
    end
  end
end
