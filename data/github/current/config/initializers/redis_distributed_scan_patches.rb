# typed: true
# frozen_string_literal: true

# Patch Redis::Distributed to support scan_each and hscan_each methods
# These methods are used by CleanLocksJob and are not natively supported by Redis::Distributed

class Redis::Distributed

  # Implements scan_each for Redis::Distributed by iterating through all nodes
  # and scanning each one individually
  def scan_each(**options, &block)
    nodes.map do |node|
      node.scan_each(**options, &block)
    end
  end

  # Implements hscan_each for Redis::Distributed by determining which node
  # contains the hash and then scanning that specific node
  def hscan_each(key, **options, &block)
    node_for(key).hscan_each(key, **options, &block)
  end
end
