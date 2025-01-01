# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_stargazers_path(entity)
      entity_path :stargazers, entity
    end

    def gh_star_path(entity)
      entity_path :star, entity
    end

    def gh_unstar_path(entity)
      entity_path :unstar, entity
    end

    private

    def entity_path(action, entity)
      path_name = "#{action}_#{entity.class.name.underscore}_path".to_sym
      expand_nwo_from path_name, entity
    end
  end
end
