# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Management
    class FeatureFlag
      FEATURE_FLAG_INVALID = "INVALID"
      FEATURE_FLAG_DISABLED = "DISABLED"
      FEATURE_FLAG_PARTIALLY_SHIPPED = "PARTIALLY_SHIPPED"
      FEATURE_FLAG_SHIPPED = "SHIPPED"

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_accessor :state

      sig { returns(T.nilable(String)) }
      attr_accessor :tracking_url

      sig { returns(T.nilable(String)) }
      attr_accessor :description

      sig { returns(T.nilable(String)) }
      attr_accessor :owning_service

      sig { returns(T.nilable(String)) }
      attr_accessor :slack_channel

      sig { returns(T.nilable(Timestamp)) }
      attr_accessor :last_updated

      sig { returns(T::Array[FeatureManagement::Management::Node]) }
      attr_accessor :nodes

      sig { returns(T.nilable(String)) }
      attr_accessor :rollout_tree_id

      sig { returns(T.nilable(T::Boolean)) }
      attr_accessor :is_big_feature

      sig { returns(T.nilable(Timestamp)) }
      attr_accessor :stale_at

      sig { returns(T.nilable(String)) }
      attr_accessor :etag

      sig { params(name: String).void }
      def initialize(name)
        @name = T.let(name, String)
        @state = T.let(FEATURE_FLAG_INVALID, String)
        @nodes = T.let([], T::Array[FeatureManagement::Management::Node])
      end

      sig { void }
      def apply_defaults!
        self.tracking_url = "https://github.com/github/feature-management/issues/438" if self.tracking_url.blank?
        self.owning_service = "-1" if self.owning_service.blank?
      end

      sig { params(data: String).returns(FeatureFlag) }
      def parse(data)
        fdata = JSON.parse(data)
        f = FeatureFlag.new(fdata["name"])
        f.state = fdata["state"]
        f.tracking_url = fdata["tracking_url"]
        f.state = fdata["state"]
        f.owning_service = fdata["owning_service"]
        f.slack_channel = fdata["slack_channel"]
        f.last_updated = fdata["last_updated"]
        f.rollout_tree_id = fdata["rollout_tree_id"]
        f.is_big_feature = fdata["is_big_feature"]
        f.stale_at = fdata["stale_at"]
        f.etag = fdata["etag"]
        fdata["nodes"].each do |n|
          node = FeatureManagement::Management::Node.new(n["name"], n["state"], n["parent"])
          node.percentage_of_calls = FeatureManagement::Management::PercentageOfCalls.new(n.dig("percentage_of_calls", "enabled"), n.dig("percentage_of_calls", "value"))
          node.percentage_of_actors = FeatureManagement::Management::PercentageOfActors.new(n.dig("percentage_of_actors", "enabled"), n.dig("percentage_of_actors", "value"))
          node.custom_gates = FeatureManagement::Management::CustomGates.new(n.dig("custom_gates", "enabled"), n.dig("custom_gates", "values"))
          f.nodes << node
        end
        f
      end
    end
  end
end
