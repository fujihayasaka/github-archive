# typed: true
# frozen_string_literal: true

module Sculk
  module MoveWork
    class ResourcesComponent < ApplicationComponent

      attr_reader :actor, :total_resources, :loaded_resources, :selected_resource_name

      def initialize(actor:, total_resources:, loaded_resources: 0, selected_resource_name: nil)
        @actor = actor
        @total_resources = (total_resources || resources_relation_count).to_i
        @loaded_resources = loaded_resources
        @selected_resource_name = selected_resource_name
      end

      memoize def resources
        relation = resources_relation
        relation = relation.reorder(
          ActiveRecord::Base.sanitize_sql_for_order([Arel.sql("field(name, ?)"), selected_resource_name]) => :desc,
        ) if selected_resource_name

        relation
          .offset(loaded_resources)
          .order(id: :desc)
          .limit(query_size)
      end

      def load_more?
        total_resources > loaded_resources + resources.count
      end

      def load_more_url
        raise NotImplementedError
      end

      def offset
        loaded_resources + resources.size
      end

      def resource_label
        raise NotImplementedError
      end

      def resources_relation
        raise NotImplementedError
      end

      def can_transfer_ownership?(resource)
        true
      end

      def non_transferrable_reason(resource)
        raise NotImplementedError
      end

      def render_header?
        loaded_resources.zero?
      end

      private

      def resources_relation_count
        resources_relation.reorder(nil).count
      end

      def query_size
        loaded_resources > 0 ? show_more_appended_results_count : initial_results_count
      end

      def initial_results_count
        4
      end

      def show_more_appended_results_count
        10
      end

      def icon_for(resource_label)
        { memex_project: :project, project: :project, repository: :repo }[resource_label]
      end

      def title_for(resource_label)
        { memex_project: "Projects (beta)", project: "Projects", repository: "Repositories" }[resource_label]
      end
    end
  end
end
