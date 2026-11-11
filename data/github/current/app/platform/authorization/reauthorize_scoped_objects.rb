# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Authorization::ReauthorizeScopedObjects
  extend T::Helpers
  extend ActiveSupport::Concern

  module ClassMethods
    def check_path_for_supported_connection(path, connections)
      return false if path.nil? && path.empty?
      filtered_path = path.select { |field| field.is_a?(String) }
      return true if filtered_path.size > 2 && filtered_path[-1] == "node" && filtered_path[-2] == "edges" && connections.include?(filtered_path[-3])
      return true if filtered_path.size > 1 && filtered_path[-1] == "nodes" && connections.include?(filtered_path[-2])
      false
    end

    def scope_items(items, context)
      return items.clone if !reauthorize_scoped_objects
      items
    end
  end

  included { reauthorize_scoped_objects(false) }

  mixes_in_class_methods(ClassMethods)
end
