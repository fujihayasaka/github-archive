# typed: true
# frozen_string_literal: true

module GitHub::Storage
  # ClusterConsensus takes a list of nodes an object was successfully replicated
  # to and determines whether the replication was sufficient.
  #
  # The node list should come in as complete URLs rather than just host names.
  # The host names are extracted and compared against the online nodes in
  # Storage::FileServer.
  class ClusterConsensus
    attr_reader :replicated_hosts
    attr_reader :quorum_hosts

    def initialize(nodes)
      hosts = extract_hosts(nodes)
      valid_hosts = GitHub::Storage::Allocator.get_all_hosts
      @replicated_hosts = hosts.select { |host| valid_hosts.include?(host) }

      online = GitHub::Storage::Allocator.get_hosts
      @quorum_hosts = replicated_hosts.select { |host| online.include?(host) }
    end

    def reached?
      quorum_hosts.size >= quorum
    end

    private

    def extract_hosts(nodes)
      nodes.map do |url|
        begin
          URI.parse(url).host
        rescue URI::InvalidURIError
          nil
        end
      end.compact.uniq
    end

    def quorum
      (GitHub.storage_replica_count / 2.0).floor + 1
    end
  end
end
