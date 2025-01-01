# typed: true
# frozen_string_literal: true

# Allows kube cluster names (e.g., dotcom-2-ash1-iad) to be used as
# Vexi actors.
module GitHub
  class VexiKubeCluster
    include GitHub::VexiActor

    def initialize(kubernetes_cluster_name)
      @kubernetes_cluster_name = kubernetes_cluster_name
      freeze
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def vexi_id
      "KubeCluster:#{@kubernetes_cluster_name}"
    end
  end
end
