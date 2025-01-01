# typed: true
# frozen_string_literal: true

module Platform
  class MutationAndClusterActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id

    def initialize(mutation_class, cluster_class)
      # eg "Platform::MutationAndClusterActor:AddComment:issues-pull-requests"
      @flipper_id = "#{self.class.name}:#{mutation_class.graphql_name}:#{cluster_class.cluster_name}"
      @vexi_id = "#{self.class.name}:#{mutation_class.graphql_name}:#{cluster_class.cluster_name}"
    end

    def to_s
      @flipper_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
