# typed: false
# frozen_string_literal: true

class ApplicationController
  module ClusterOwnershipDependency
    extend ActiveSupport::Concern

    class ClusterDependencies
      def initialize
        @global_required_dependencies = []
        @global_optional_dependencies = []

        @action_required_dependencies = {}
        @action_optional_dependencies = {}
      end

      def add_required_clusters(clusters, only: nil)
        if only.nil?
          @global_required_dependencies.concat(clusters)
        else
          only.each do |action|
            @action_required_dependencies[action.to_sym] ||= []
            @action_required_dependencies[action.to_sym].concat(clusters)
          end
        end
      end

      def add_optional_clusters(clusters, only: nil)
        if only.nil?
          @global_optional_dependencies.concat(clusters)
        else
          only.each do |action|
            @action_optional_dependencies[action] ||= []
            @action_optional_dependencies[action].concat(clusters)
          end
        end
      end

      def required_clusters_for(action)
        @global_required_dependencies + (@action_required_dependencies[action.to_sym] || [])
      end

      def optional_clusters_for(action)
        @global_optional_dependencies + (@action_optional_dependencies[action.to_sym] || [])
      end

      def actions
        (@action_required_dependencies.keys | @action_optional_dependencies.keys).map(&:to_s).to_set
      end
    end

    included do
      delegate :cluster_dependencies, to: :class

      class << self
        attr_accessor :cluster_dependencies
      end
    end

    class_methods do
      def depends_on_clusters(*clusters, only: nil, optional: false)
        self.cluster_dependencies ||= ClusterDependencies.new

        clusters = clusters.select { |c| c.is_a?(Class) && c < ApplicationRecord::Base }

        if optional
          self.cluster_dependencies.add_optional_clusters(clusters, only: only)
        else
          self.cluster_dependencies.add_required_clusters(clusters, only: only)
        end
      end
    end

    def required_clusters
      return unless self.class.cluster_dependencies
      self.class.cluster_dependencies.required_clusters_for(action_name.to_sym)
    end

    def optional_clusters
      return unless self.class.cluster_dependencies
      self.class.cluster_dependencies.optional_clusters_for(action_name.to_sym)
    end

    def disable_optional_clusters
      return yield unless GitHub.disable_optional_clusters?
      optional_clusters = self.optional_clusters
      return yield if optional_clusters.blank?

      ActiveRecord::Base.disable_queries_to_databases(optional_clusters) do
        yield
      end
    end
  end
end
