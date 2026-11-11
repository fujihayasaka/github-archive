# frozen_string_literal: true

require "terminal-table"

module FlipperActor
  extend ActiveSupport::Concern

  FLIPPER_ID_SEPARATOR = ":"

  def flipper_id
    "#{self.class.name}#{FLIPPER_ID_SEPARATOR}#{id}"
  end

  def feature_enabled?(feature_name)
    tags = feature_tags(operation: "query", feature_name: feature_name)
    MetricsClient.increment("feature_flag.call", tags: tags)
    ActiveRecord::Base.connected_to(role: :reading) do
      Dependabot.flipper[feature_name].enabled?(self)
    end
  end

  def enable_feature(feature_name)
    tags = feature_tags(operation: "enable", feature_name: feature_name)
    MetricsClient.increment("feature_flag.call", tags: tags)
    Dependabot.flipper[feature_name].enable_actor(self)
  end

  def disable_feature(feature_name)
    tags = feature_tags(operation: "disable", feature_name: feature_name)
    MetricsClient.increment("feature_flag.call", tags: tags)
    Dependabot.flipper[feature_name].disable_actor(self)
  end

  private

  def feature_tags(operation:, feature_name:)
    {
      "feature_flag.key" => feature_name,
      "feature_flag.operation" => operation,
    }
  end
end
