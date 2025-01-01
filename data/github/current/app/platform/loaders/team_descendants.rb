# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TeamDescendants < Platform::Loader
      def self.load(team, immediate_only:)
        return ::Promise.resolve([]) unless team.present?

        self.for(immediate_only: immediate_only).
          load(team.tree_path).then do |(_parent_id, descendant_ids)|
            descendant_ids
          end
      end

      def self.load_all(teams, immediate_only:)
        return ::Promise.resolve({}) if teams.empty?

        loader = self.for(immediate_only: immediate_only)

        ::Promise.all(
          teams.map do |team|
            loader.load(team.tree_path).then do |nodes|
              nodes
            end
          end,
        ).then do |teams_with_descendant_ids|
          results = {}

          teams_with_descendant_ids.each do |(parent_id, descendant_ids)|
            results[parent_id] = descendant_ids
          end

          results
        end
      end

      attr_reader :immediate_only

      def initialize(immediate_only:)
        @immediate_only = immediate_only
      end

      # Internal: fetch the descendant Team IDs given a list of parent Team
      # tree paths.
      #
      # NOTE: The returned Hash should set the value of the parent Team ID to
      # an empty Array even if no descendant Team IDs are found. This is
      # a requirement of the batch loading resolution step and a core contract
      # of this loader.
      #
      # Returns a Hash{parent_id Integer => Array[descendant_id Integer...]}.
      def fetch(tree_paths)
        return {} if tree_paths.empty?

        sql = Arel.sql(<<~SQL)
          SELECT
            id, tree_path
          FROM `#{Team.table_name}`
          WHERE
        SQL

        tree_paths.each_with_index do |tree_path, i|
          sql += Arel.sql "OR" if i > 0

          path = wildcard_path(tree_path)
          if immediate_only
            sql += Arel.sql <<~SQL, like_path: path, not_like_path: wildcard_path(path)
              (
                tree_path LIKE :like_path AND
                tree_path NOT LIKE :not_like_path
              )
            SQL
          else
            sql += Arel.sql "tree_path LIKE :like_path", like_path: path
          end
        end

        results = {}
        sql_results = Team.connection.select_rows(sql)

        tree_paths.each do |parent_tree_path|
          parent_node = Team::Nested::TeamTreeNode.new(parent_tree_path)
          parent_id = node_id(parent_tree_path)

          results[parent_tree_path] = [
            parent_id,
            select_descendants(parent_id, sql_results),
          ]
        end

        results
      end

      private

      def select_descendants(parent_id, results)
        selected = []

        results.each do |(descendant_id, descendant_tree_path)|
          descendant_node = Team::Nested::TeamTreeNode.new(descendant_tree_path)

          if immediate_only
            selected << descendant_id if descendant_node.parent_id == parent_id
          else
            selected << descendant_id if descendant_of?(descendant_node, parent_id)
          end
        end

        selected
      end

      def path_string(tree_path)
        Arvore::PathString.new(tree_path)
      end

      def wildcard_path(tree_path)
        path_string(tree_path).raw_append("%")
      end

      def node_id(tree_path)
        path_string(tree_path).id
      end

      def descendant_of?(node, id)
        path_string(node.path).include?(id)
      end
    end
  end
end
