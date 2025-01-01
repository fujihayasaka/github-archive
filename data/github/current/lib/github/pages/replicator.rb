# typed: true
# frozen_string_literal: true

# This class defines a strategy for replicating a Pages site to a specified number of hosts
# distributed across data centers.

class GitHub::Pages::Replicator
  def initialize(repository, preview = false)
    @repository = repository
    @preview = preview
  end

  def pages_beta_replication_strategy?
    return false if GitHub.enterprise?
    return false if repository.nil?
    (GitHub.flipper[:pages_beta_replication_strategy].enabled?(repository) || GitHub.flipper[:pages_beta_replication_strategy].enabled?(repository.owner)) &&
      !repository.nwo.eql?("github/pages.github.com")
  end

  def replication_strategy
    return @replication_strategy if defined?(@replication_strategy)

    # Currently disabled in Enterprise
    return (@replication_strategy = nil) if GitHub.enterprise?
    @replication_strategy = if preview
      GitHub::Pages::ReplicationStrategy.new(replica_counts: 2, data_centers: [%w[ac4 ash1 va3][rand(0..2)]])
    elsif pages_beta_replication_strategy?
      GitHub.pages_beta_replication_strategy
    else
      GitHub.pages_replication_strategy
    end
  end

  def voting_count
    return GitHub.pages_replica_count unless preview
    [2, GitHub.pages_replica_count].min
  end

  def non_voting_count
    return 0 unless write_non_voting_replicas?
    return GitHub.pages_non_voting_replica_count unless preview
    [2, GitHub.pages_non_voting_replica_count].min
  end

  def pages_deployer_api_client
    return @pages_deployer_api_client if defined?(@pages_deployer_api_client)
    @pages_deployer_api_client = Page::Twirp::RequestClient.new(service_name: "replicator")
  end

  def pages_deployer_allocated_hosts
    return [] unless use_pages_deployer_allocation?
    pages_deployer_api_client.request_deployment_hosts
  end

  def use_pages_deployer_allocation?
    return false if GitHub.enterprise?

    # TODO: modified remove repository true check and feature flag check together after we 100% enabled feature flag and start to reuse it in the migration job.
    return false if repository.nil?
    GitHub.flipper[:pages_deployer_allocation].enabled?(repository) || GitHub.flipper[:pages_deployer_allocation].enabled?(repository.owner)
  end

  def hosts(build_id)
    return { voting: pages_deployer_allocated_hosts, non_voting: [] } if use_pages_deployer_allocation?
    GitHub::Pages::Allocator.hosts_for_new_replicas(
      build_id: build_id,
      replication_strategy: replication_strategy,
      voting: voting_count,
      non_voting: non_voting_count,
    )
  end

  def hosts_with_datacenter(build_id)
    assigned_hosts = hosts(build_id)
    assigned_hosts[:voting].map { |host| { name: host, non_voting: false, datacenter: extract_datacenter(host) } } +
    assigned_hosts[:non_voting].map { |host| { name: host, non_voting: true, datacenter: extract_datacenter(host) } }
  end

  def repository
    @repository
  end

  def preview
    @preview
  end

  def write_non_voting_replicas?
    return @write_non_voting_replicas if defined?(@write_non_voting_replicas)
    @write_non_voting_replicas = GitHub.pages_non_voting_replica_count.to_i > 0
  end

  def extract_datacenter(host)
    return nil if datacenter_matcher.nil?
    result = datacenter_matcher.match(host)
    return result if result.nil?
    result[1]
  end

  private

  def datacenter_matcher
    return nil if GitHub.enterprise?

    # for azure-eastus host, we use availaibility zone, so we don't need to match datacenter match here.
    return nil if use_pages_deployer_allocation?
    return @datacenter_matcher if defined?(@datacenter_matcher)
    @datacenter_matcher = /pages-dfs-\w+\.(#{replication_strategy.data_centers.join('|')})-\w+\.github\.net/m
  end
end
