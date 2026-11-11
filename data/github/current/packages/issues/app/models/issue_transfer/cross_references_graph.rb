# typed: true
# frozen_string_literal: true

class IssueTransfer::CrossReferencesGraph
  DEFAULT_SETTINGS = {
    cross_references_fetch_batch_size: 1000
  }

  attr_reader :ids, :edges

  def self.from_repo(repo_id, settings = {})
    ids, edges = get_ids_and_edges_from_repo(repo_id, DEFAULT_SETTINGS.merge(settings))

    new(ids, edges)
  end

  def initialize(ids, edges)
    @ids = ids.freeze
    @edges = edges.freeze
    @neighbors = Hash.new { |h, k| h[k] = [] }
  end

  def neighbors?(id)
    neighbors(id).size > 0
  end

  def neighbors(id)
    return @neighbors[id] if @neighbors.has_key?(id)

    @neighbors[id] = (referencing_neighbors(id) + referenced_neighbors(id)).uniq
  end

  def referencing_neighbors(id)
    return [] unless edges.has_key?(id)

    edges[id][:in]
  end

  def referenced_neighbors(id)
    return [] unless edges.has_key?(id)

    edges[id][:out]
  end

  def self.get_ids_and_edges_from_repo(repo_id, settings)
    repo = Repositories::Public.find_active!(repo_id)
    ids = get_ids_from_repo(repo)

    edges = Hash.new { |h, k| h[k] = { in: [], out: [] } }

    # Scoping only issues here, because this is built for transferring issues
    # after an issue-only migration. In other scenarios, issues might be referencing
    # PRs, discussions, etc, and those need to be handled separately.
    scope = CrossReference.issues.referencing("Issue")

    # Fetching cross references in batches, otherwise the query will timeout.
    ids.each_slice(settings[:cross_references_fetch_batch_size]) do |ids_slice|
      Rails.logger.info "Fetching cross references for #{ids_slice.size} subjects."

      out_refs = scope.where(source_id: ids_slice).pluck(:source_id, :target_id)
      in_refs  = scope.where(target_id: ids_slice).pluck(:source_id, :target_id)

      xrefs_slice = out_refs + in_refs

      xrefs_slice.each do |source_id, target_id|
        edges[source_id][:out] << target_id
        edges[target_id][:in] << source_id
      end
    end

    # Remove duplicates.
    ids.each do |id|
      next unless edges.has_key?(id)
      edges[id][:out] = edges[id][:out].uniq
      edges[id][:in] = edges[id][:in].uniq
    end

    [ids, edges]
  end

  private_class_method :get_ids_and_edges_from_repo


  def self.get_ids_from_repo(repo)
    repo.issues.without_pull_requests.pluck(:id)
  end

  private_class_method :get_ids_from_repo
end
