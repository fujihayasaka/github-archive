# typed: true
# frozen_string_literal: true

class RebuildAuditLogsJob < ApplicationJob
  queue_as :index_bulk

  attr_reader :cluster, :lucene_check, :primary_cluster

  # Iterate over each audit log search index and copy the audit log entries
  # from the current primary to a new search index. The new search index
  # will be promoted to the primary role, and the old primary index will be
  # deleted.
  #
  # After all audit log indices have been rebuilt the new audit log
  # template will be promotoed to the primary role, and the old audit log
  # template will be destroyed.
  #
  # Returns this job instance.
  def perform(cluster: "default", lucene_check: false, primary_cluster: true)
    @lucene_check = lucene_check
    @cluster = cluster
    @primary_cluster = primary_cluster

    return self unless rebuild_primaries?

    remaining.each do |primary_index_config|
      dest   = destination_index_config(primary_index_config.slice)
      repair = copy_to_destination(dest.name)
      repair.reset!

      finish_copy(primary_index_config.index, dest.index)
    end

    finish_rebuild
    self
  end

  # Internal: Finish the rebuild process by promoting the new audit log
  # index template to the primary role and deleting the old index template.
  #
  # Returns this job instance.
  def finish_rebuild
    return unless remaining.empty?

    if primary_cluster
      primary_template = Elastomer.router.primary_template(Elastomer::Indexes::AuditLog, cluster)
      primary_template.remove_primary
      template.add_primary
      primary_template.destroy
    end
    self
  end

  # Internal: Returns the audit log index template that will be used when
  # creating the destination audit log indices.
  def template
    @template ||= (most_recent_writable_non_primary_template(cluster) || create_writable_template!(cluster))
  end

  # Internal: Returns the fullname of the audit log index template that will
  # be used to create the new indices.
  def template_name
    template.fullname
  end

  # Internal: Selects the most recent writable non primary tenplate
  def most_recent_writable_non_primary_template(cluster)
    template_type = Elastomer.router.to_template_type(Elastomer::Indexes::AuditLog)

    SearchIndexTemplateConfiguration.
      where(template_type: template_type, is_writable: true, is_primary: false, cluster: cluster).
      order("created_at DESC").first
  end

  # Internal: Creates a writable template for audit logs in the given cluster
  def create_writable_template!(cluster)
    if Rails.env.production? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        !GitHub.enterprise? && cluster == "default"
      raise ArgumentError, "`default` is not a valid cluster in production"
    end

    name = Elastomer.router.next_available_template_name(Elastomer::Indexes::AuditLog)
    template = SearchIndexTemplateConfiguration.new \
      fullname:    name,
      cluster:     cluster,
      is_writable: true,
      is_primary:  false
    template.save!
    template
  end

  # Internal: Finish the copy process by validating that all the audit log
  # entries have been copied over. Then promote the new index to the primary
  # role and delete the old index.
  #
  # primary - The primary audit log Index instances
  # dest    - The new audit log destination Index
  #
  # Returns `true` if things finished properly and `false` if not
  def finish_copy(primary, dest)
    # refresh the index so our document counts are accurate
    dest.refresh

    primary_count = docs_count(primary)
    dest_count    = docs_count(dest)

    # sanity check that all the audit log entries were copied to the destination
    return false if primary_count != dest_count && current_index_name != primary.name

    if primary_cluster
      primary.update_config("read" => false, "write" => false)
      Elastomer::SearchIndexManager.promote_index_to_primary(name: dest.name, index_class: dest.class)
      Elastomer::SearchIndexManager.delete_index(name: primary.name, index_class: primary.class, force: true) if exists?(primary)
    end

    true
  end

  # Internal: Returns `true` if the Elasticsearch index for the given
  # `index` actually exists. This method returns `false` if the
  # `index` is pointing to an alias and not an actual index.
  #
  # index - an AuditLog Index instance
  #
  def exists?(index)
    index = index.index
    return false unless index.exists?

    aliases = index.get_alias(index.name)
    aliases.empty?
  end

  # Internal: Returns the name of the current primary audit log index.
  def current_index_name
    slice = Elastomer::Indexes::AuditLog.slicer.slice_from_value(Time.now.utc)
    index = Elastomer.router.primary(Elastomer::Indexes::AuditLog, slice)
    index.name
  end

  # Internal: Copy all audit log entries from the primary index to the new
  # audit log index identified by the given `idnex_name`.
  #
  # index_name - The name of the destination index
  #
  def copy_to_destination(index_name)
    repair = RepairAuditLogIndexJob.new(index_name)
    repair.enable
    repair.activate

    until repair.finished?
      break if repair.disabled?
      repair.repair!
    end

    repair
  ensure
    T.must(repair).deactivate
  end

  # Internal: Returns an AuditLog index configuration for the given `slice`.
  # The index is not guaranteed to exist.
  #
  # slice - month slice String "2017-04"
  #
  # Returns an AuditLog index configuration.
  def destination_index_config(slice)
    ary = existing.select { |ic| ic.slice == slice }

    if ary.empty?
      index_name = Elastomer::SearchIndexManager.create_index_from_template(template: template, slice: slice)
      Elastomer.router.get_index_config(index_name)
    else
      ary.first
    end
  end

  # Internal: Return the number of documents in the given search index.
  #
  # index - an Elastomer::Index instance
  #
  # Returns the number of documents in the search index.
  def docs_count(index)
    response = index.client.get("/#{index.name}/_stats/docs")
    if response.success?
      response.body.dig("indices", index.name, "primaries", "docs", "count")
    end
  end

  # Internal: Returns `true` if the primary audit log indices should be
  # rebuilt based on the lucene version number of the indices. This will
  # always return true if a `lucene_check` version has not been given - i.e.
  # the default behavior is to rebuild the audit logs in the absence of a
  # specific lucene version.
  def rebuild_primaries?
    return true unless lucene_check
    primaries.any? { |ic| lucene_version(ic) < lucene_check }
  end

  # Internal: Returns an Array of IndexConfig objects for the primary audit
  # log search indices.
  def primaries
    @primaries ||= begin
                     ary = Elastomer.router.primary(Elastomer::Indexes::AuditLog, "*") || []
                     ary.sort_by(&:name)
                   end
  end

  # Internal: Returns an Array of IndexConfig objects for the new audit log
  # search indices created from the audit log search index template.
  def existing
    @existing ||= begin
                    ary = Elastomer.router.index_map.all_index_slices(template_name) || []
                    if lucene_check
                      ary.select! { |ic| lucene_version(ic) >= lucene_check }
                    end
                    ary.sort_by(&:name)
                  end
  end

  # Internal: Returns an Array of the remaining primary indices that need to
  # be rebuilt. This Array can be empty if there are no more primaries to
  # rebuild.
  def remaining
    @existing = @primaries = nil  # force the index configs to reload
    slices = Set.new(existing.map(&:slice))
    ary = primaries.dup
    ary.delete_if { |cfg| slices.include?(cfg.slice) }
    ary
  end

  # Internal: Returns the Lucene version for the given index.
  #
  # index_config - an Elastomer::Router::IndexConfig instance
  #
  # Returns the Lucene version String.
  def lucene_version(index_config)
    index = Elastomer.router.client(index_config.cluster).index(index_config.name)
    hash  = index.segments

    ary = hash.dig("indices", index.name, "shards").values.flatten
    ary.map! { |h| h.dig("segments").values }
    ary.flatten!
    ary.map! { |h| h.dig("version") }
    ary.uniq.sort.first.to_s
  end
end
