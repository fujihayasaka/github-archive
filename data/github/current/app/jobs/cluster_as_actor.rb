# typed: true
# frozen_string_literal: true
class ClusterAsActor
  include GitHub::FlipperActor
  include GitHub::VexiActor

  def self.find_by_id(cluster) # rubocop:disable GitHub/FindByDef
    new(cluster.to_s)
  end

  def initialize(index_key)
    @index_key = index_key
  end

  def flipper_id
    "#{self.class.name}:#{@index_key}"
  end

  def vexi_id
    flipper_id
  end
end
