# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TeamDescendants < Platform::Loader
      def self.load(team, immediate_only:, optimized: false)
        return ::Promise.resolve([]) unless team.present?

        self.for(immediate_only:, optimized:).
          load(self.key(team, optimized:)).then do |(_parent_id, descendant_ids)|
            descendant_ids
          end
      end

      def self.load_all(teams, immediate_only:, optimized: false)
        return ::Promise.resolve({}) if teams.empty?

        loader = self.for(immediate_only:, optimized:)

        ::Promise.all(
          teams.map do |team|
            loader.load(self.key(team, optimized:)).then do |nodes|
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
      attr_reader :optimized

      def initialize(immediate_only:, optimized:)
        @immediate_only = immediate_only
        @optimized = optimized
      end

      private_class_method def self.key(team, optimized:)
        if optimized
          { id: team.id, tree_path: team.tree_path }
        else
          team.tree_path
        end
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
      def fetch(keys)
        start = Time.current.utc
        result = if optimized
          fetch_optimized(keys)
        else
          fetch_control(keys)
        end
        GitHub.logger.info("Fetched team descendants",
          "gh.duration_ms" => (Time.current.utc - start) * 1000,
          "gh.teams.optimized" => optimized,
          "gh.teams.immediate_only" => immediate_only,
          "gh.teams.keys" => keys
        )
        result
      end

      private

      def fetch_control(tree_paths)
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

      def fetch_optimized(teams)
        return {} if teams.empty?

        sql = Arel.sql(<<~SQL)
          SELECT
            id, tree_path
          FROM `#{Team.table_name}`
          WHERE
        SQL

        teams.pluck(:tree_path).each_with_index do |tree_path, i|
          sql += Arel.sql "OR" if i > 0

          path = tree_path + "/%"
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

        sql_results = Team.connection.select_rows(sql)

        results = {}
        descendant_team_ids_by_parent_tree_path = {}
        shortest_tree_path_length = -1
        teams.each do |team|
          descendant_team_ids = []
          results[team] = [team[:id], descendant_team_ids]
          descendant_team_ids_by_parent_tree_path[team[:tree_path]] = descendant_team_ids
          key_length = T.let(team[:tree_path].length, Integer)
          shortest_tree_path_length = key_length if key_length < shortest_tree_path_length || shortest_tree_path_length == -1
        end

        sql_results.each do |id, tree_path|
          if immediate_only
            slash_index = tree_path.rindex("/")
            next unless slash_index
            ancestor_path = tree_path[0...slash_index]
            if (descendant_team_ids = descendant_team_ids_by_parent_tree_path[ancestor_path])
              descendant_team_ids << id
            end
          else
            slash_index = T.let(shortest_tree_path_length - 1, T.nilable(Integer))
            while slash_index = tree_path.index("/", T.must(slash_index) + 1)
              team_ids = descendant_team_ids_by_parent_tree_path[tree_path[0, slash_index]]
              team_ids << id if team_ids
            end
          end
        end

        results
      end

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
