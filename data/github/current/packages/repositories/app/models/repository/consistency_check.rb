# typed: true
# frozen_string_literal: true

module Repository::ConsistencyCheck
  extend T::Helpers
  requires_ancestor { Repository }

  # Run verification checks on the repository's network structure. Yield each
  # error or warning message to the block when given.
  #
  # Returns an array of error and warning messages. These are simple strings
  # with "error:" or "warning:" prefixes.
  def verify_network_consistency(&block)
    res = []
    report = lambda { |note| (block && block.call(note)); res << note }
    verify_root_repository &report
    verify_parentage &report
    res
  end

  # Verify exactly one network root repository exists. The root is the
  # repository whose parent_id is nil.
  def verify_root_repository
    repos = network_repositories.where("parent_id IS NULL")
    if repos.size == 0
      yield "error: network has no root"
    elsif repos.size > 1
      yield "warning: network has #{repos.size} roots"
    end
  end

  # Verify that parent relationships are valid for all repositories in the
  # network. This checks for missing records, mixed networks, and public forks
  # of private repositories.
  def verify_parentage
    parent_ids = network_repositories.forks.pluck(Arel.sql("DISTINCT parent_id"))
    parents = Repository.where(id: parent_ids).to_a

    missing_ids = parent_ids - parents.map(&:id)
    network_repositories.where(parent_id: missing_ids).each do |repository|
      yield "error: repository #{repository.name_with_owner} parent is missing: #{repository.parent_id}"
    end

    different_networks = parents.select { |parent| parent.network_id != network_id }
    network_repositories.where(parent_id: different_networks).each do |repository|
      yield "error: repository #{repository.name_with_owner} parent is in different network " \
          "(#{network_id} != #{repository.parent.network_id.inspect})"
    end

    deleted_parents = parents.reject(&:active?)
    network_repositories.where(parent_id: deleted_parents).each do |repository|
      yield "error: repository #{repository.name_with_owner} parent is deleted"
    end

    private_parents = parents.select(&:private?)
    network_repositories.public_scope.where(parent_id: private_parents).each do |repository|
      yield "error: public repository #{repository.name_with_owner} parent is private"
    end
  end
end
