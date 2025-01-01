require_relative "snapshot_diff_model"

module Snapshots
  # Change is an abstract class representing an Addition, Removal, or Update
  # operation in a diff. Ultimately we'll represent the whole diff as a flat
  # array of Change objects (see #changes method).
  class Change
    def addition?
      self.class == Addition
    end

    def removal?
      self.class == Removal
    end

    def update?
      self.class == Update
    end

    def ==(other)
      return false unless self.class == other.class
      self.instance_variables.all? { |var| self.instance_variable_get(var) == other.instance_variable_get(var) }
    end

    def eql?(other)
      self.==(other)
    end

    # reconstruct the package name (in dg-api's expected format) from the twirp change object's package_url
    def self.package_name_from_twirp(change)
      purl = PackageUrls::PackageUrl.from_purl(purl: change.package_url)

      name = purl.name
      if purl.namespace.present?
        name = "#{purl.namespace}/#{name}"
      end

      # Maven dependencies should use `:` as a separator, not `/`
      if change.package_url.start_with?("pkg:maven/")
        name = name.sub("/", ":")
      end

      name
    end

    def package_manager
      return @package_manager if defined?(@package_manager)

      path = ManifestAdapters.normalize_path(path: self.manifest_path)
      filename = File.basename(path)

      # Special case: match package managers that are only supported by snapshots
      if package_manager = ManifestAdapters.snapshot_only_package_manager(filename)
        return @package_manager = package_manager.name
      end

      adapter = ManifestAdapters.recognized_path?(filename: filename, path: path)
      # in case we can't figure out the adapter from the path, try the purl.
      # this may happen in the case of a dependency snapshot, where we don't
      # require that the manifest be a recognized type.
      adapter ||= ManifestAdapters.from_purl(self.purl)

      unless adapter
        # dependency snapshots can have unknown manifests to DG.
        # Log it for awareness, but should not be an error
        DependencyGraph.logger.info("snapshot includes an unrecognized manifest type",
          "gh.dependency_graph.manifest.not_recognized_error" => true,
          "gh.dependency_graph.manifest.filename" => filename.inspect,
          "gh.dependency_graph.manifest.path" => path.inspect,
          "gh.dependency_graph.manifest.filename_encoding" => filename&.encoding.to_s,
          "gh.dependency_graph.manifest.path_encoding" => path&.encoding.to_s,
        )

        return @package_manager = :unknown
      end

      @package_manager = adapter.package_manager.name
    end
  end

  class Addition < Change
    attr_reader :manifest_path, :name, :version, :scope, :purl, :snapshot_metadata

    def to_model
      Snapshots::DependencyDiffModel.new(
        name: @name,
        target_version: @version,
        change_type: :added,
        ecosystem: package_manager,
        scope: @scope,
        target_purl: @purl,
      )
    end

    def self.from_dependency(manifest_path:, dependency:)
      Snapshots::Addition.new(
        manifest_path: manifest_path,
        name: dependency.name,
        version: dependency.version,
        scope: dependency.scope,
        purl: dependency.purl
      )
    end

    def self.from_twirp(change)
      scope = change.scope == :NONE ? "runtime" : change.scope.to_s.downcase
      # All snapshot versions are exact
      version = change.version.empty? ? "" : "= #{change.version}"
      Snapshots::Addition.new(
        manifest_path: change.manifest,
        name: Change.package_name_from_twirp(change),
        version: version,
        scope: scope,
        purl: change.package_url,
        snapshot_metadata: change.snapshot_metadata.to_h
      )
    end

    def initialize(manifest_path:, name:, version:, scope:, purl: nil, snapshot_metadata: nil)
      @manifest_path = manifest_path
      @name = name
      @version = version
      @scope = scope
      @purl = purl
      @snapshot_metadata = snapshot_metadata
    end
  end

  class Removal < Change
    attr_reader :manifest_path, :name, :version, :scope, :purl, :snapshot_metadata

    def to_model
      Snapshots::DependencyDiffModel.new(
        name: @name,
        base_version: @version,
        change_type: :removed,
        ecosystem: package_manager,
        scope: @scope,
        base_purl: @purl,
      )
    end

    def self.from_dependency(manifest_path:, dependency:)
      Snapshots::Removal.new(
        manifest_path: manifest_path,
        name: dependency.name,
        version: dependency.version,
        scope: dependency.scope,
        purl: dependency.purl
      )
    end

    def self.from_twirp(change)
      scope = change.scope == :NONE ? "runtime" : change.scope.to_s.downcase
      Snapshots::Removal.new(
        manifest_path: change.manifest,
        name: Change.package_name_from_twirp(change),
        version: change.version,
        scope: scope,
        purl: change.package_url,
        snapshot_metadata: change.snapshot_metadata.to_h
      )
    end

    def initialize(manifest_path:, name:, version:, scope:, purl: nil, snapshot_metadata: nil)
      @manifest_path = manifest_path
      @name = name
      @version = version
      @scope = scope
      @purl = purl
      @snapshot_metadata = snapshot_metadata
    end
  end

  class Update < Change
    attr_reader :manifest_path, :name, :old_version, :new_version, :scope, :old_purl, :new_purl, :new_scope, :purl

    def to_model
      Snapshots::DependencyDiffModel.new(
        name: @name,
        base_version: @old_version,
        target_version: @new_version,
        change_type: :updated,
        ecosystem: package_manager,
        scope: @scope,
        base_purl: @old_purl,
        target_purl: @new_purl,
      )
    end

    def initialize(manifest_path:, name:, old_version:, new_version:, scope:, old_purl: nil, new_purl: nil, new_scope: nil)
      @manifest_path = manifest_path
      @name = name
      @old_version = old_version
      @new_version = new_version
      @scope = scope
      @old_purl = old_purl
      @new_purl = new_purl
      @new_scope = new_scope
      @purl = new_purl
    end
  end

  # The Diff class is responsible for comparing two snapshots and outputting a
  # diff in several potential formats. Of these, #to_model is the only one
  # that currently gets used in production, but #simple_diff is also useful for
  # testing/debugging.
  #
  # Diffing itself works like this:
  #   1. Convert all the dependencies from all of the manifests in each snapshot into ManifestDependencySets.
  #   2. Compare the two sets to get raw removals and additions.
  #   3. The #changes method takes those raw removals and additions computes
  #      changes (i.e., a combined removal+addition). It returns an array of Change
  #      objects that can be worked into whatever format.
  #   4. #to_model takes the #changes array and converts it into the proper response format.
  class Diff
    attr_reader :base, :target, :added, :removed, :base_set, :target_set, :decompose_updates

    # Given a snapshot, non-destructively performs the additions and removals
    # from this diff to their respective manifests in that snapshot. Returns a
    # new snapshot.
    #
    # Snapshots::Diff.new(base, target).apply(base) == target
    #   (only applies if dependencies are unique in each manifest)
    def apply(snapshot)
      apply_to_snapshot(snapshot: snapshot)
    end

    # Returns a flat array of Additions, Removals, and Updates
    def changes
      process!
      return @changes if defined?(@changes) && @changes
      ret = []

      changes = []
      @added.collect.group_by(&:manifest_path).each do |path, mdependencies|
        mdependencies.each do |md|
          changes.push(Snapshots::Addition.from_dependency(
            manifest_path: path,
            dependency: md.to_dependency
          ))
        end
      end

      @removed.collect.group_by(&:manifest_path).each do |path, mdependencies|
        mdependencies.each do |md|
          changes.push(Snapshots::Removal.from_dependency(
            manifest_path: path,
            dependency: md.to_dependency
          ))
        end
      end

      if decompose_updates
        ret = changes
      else
        ret = compose_updates(changes)
      end
      @changes = ret
    end

    def process!
      @base_set ||= Snapshots::ManifestDependencySet.new(@base)
      @target_set ||= Snapshots::ManifestDependencySet.new(@target)

      @added ||= @target_set - @base_set
      @removed ||= @base_set - @target_set
    end

    def to_model
      changed_manifests = changes.collect.group_by(&:manifest_path).map do |path, changes_|
        next if changes_.empty?
        package_manager = changes_[0].package_manager
        # usually all the changes will be for the same package manager, but not always. if not,
        # we should consider it an unknown manifest type.
        unless changes_.all? { |c| c.package_manager == package_manager }
          package_manager = :unknown
        end
        Snapshots::ManifestDiffModel.new(
          file_path: path,
          package_manager: package_manager,
          dependencies: changes_.sort_by(&:name).map(&:to_model))
      end

      Snapshots::SnapshotDiffModel.new(
        github_repository_id: @target.github_repository_id,
        base_sha: @base.metadata.sha,
        target_sha: @target.metadata.sha,
        changed_manifests: changed_manifests,
      )
    end

    def to_dependency_snapshot_model
      changed_manifests = changes.collect.group_by(&:manifest_path).map do |path, changes_|
        next if changes_.empty?
        Snapshots::ManifestDiffModel.new(
          file_path: path,
          package_manager: changes_[0].package_manager, # all the changes_ will be for the same manifest
          dependencies: changes_.sort_by(&:name).map(&:to_dependency_snapshot_model))
      end

      Snapshots::SnapshotDiffModel.new(
        github_repository_id: @target.github_repository_id,
        base_sha: @base.sha,
        target_sha: @target.sha,
        changed_manifests: changed_manifests,
        dependency_snapshot: true
      )
    end

    def simple_diff
      process!
      manifest_adds = @added.to_manifests
      manifest_removals = @removed.to_manifests

      snapshot_changes = changes.filter { |c| c.try(:snapshot_metadata) }
      snapshot_additions = snapshot_changes.filter(&:addition?)
      snapshot_removals = snapshot_changes.filter(&:removal?)

      {
        added: manifest_adds,
        removed: manifest_removals,
        snapshot_added: snapshot_additions,
        snapshot_removed: snapshot_removals
      }
    end

    def inspect
      simple_diff
    end

    def combine_with_twirp_diff(twirp_diff)
      changes # ensure that @changes has been populated
      additions = twirp_diff.data.dependency_changes.filter { |c| c.change_type == :ADDED }.map { |c| Snapshots::Addition.from_twirp(c) }
      removals = twirp_diff.data.dependency_changes.filter { |c| c.change_type == :REMOVED }.map { |c| Snapshots::Removal.from_twirp(c) }
      snapshot_changes = additions + removals
      unless decompose_updates
        snapshot_changes = compose_updates(snapshot_changes)
      end

      # remove any changes from dg-api for manifests that are in ds-api
      snapshot_manifests = snapshot_changes.map { |change|
        DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path(change.manifest_path)
      }.uniq
      @changes.reject! { |c| c.manifest_path.in?(snapshot_manifests) }

      @changes += snapshot_changes
      self
    end

    def initialize(base_snapshot, target_snapshot, decompose_updates: false)
      @base = base_snapshot
      @target = target_snapshot
      @decompose_updates = decompose_updates
    end

    private

    # Although the option is called `decompose_updates`, updates always start
    # out decomposed anyway (i.e., they appear as separate REMOVAL and ADDITION
    # changes).
    # This method takes the decomposed updates and combines them into a single UPDATE change where possible.
    # It should be called when `decompose_updates` is false.
    def compose_updates(changes)
      ret = []
      # group all the change objects into a nested map of scope -> manifest_path -> name -> [changes]
      grouped = changes.group_by(&:scope).transform_values { |scoped_changes|
        scoped_changes.group_by(&:manifest_path).transform_values { |changes|
          changes.collect.group_by(&:name)
        }
      }
      grouped.each do |scope, scoped_names_to_changes|
        scoped_names_to_changes.each do |manifest_path, names_to_changes|
          names_to_changes.each do |name, changes|
            # only additions or subtractions, not an update
            all_additions_or_removals = changes.all?(&:addition?) || changes.all?(&:removal?)
            if all_additions_or_removals
              changes.each do |change|
                ret.push change
              end
            else # process the updates
              updates = format_updates(changes)
              ret += updates
            end
          end
        end
      end
      ret
    end

    # Given an array of changes *for the same manifest, name, and scope*, format Update objects
    # for matching pairs of removals and additions.
    # In all likelihood, this will only ever be called by `compose_updates`.
    def format_updates(changes)
      ret = []
      additions = changes.filter(&:addition?).sort_by(&:version)
      removals = changes.filter(&:removal?).sort_by(&:version)
      # match removals and additions pairwise in version order as much as possible
      # there will be leftovers if there are more removals than additions or vice-versa
      overlap = [additions.count, removals.count].min
      0.upto(overlap - 1).each do |i|
        name = additions[i].name
        scope = removals[i].scope
        manifest_path = additions[i].manifest_path
        ret.push(Snapshots::Update.new(
          manifest_path: manifest_path,
          name: name,
          old_version: removals[i].version,
          new_version: additions[i].version,
          scope: scope,
          old_purl: removals[i].purl,
          new_purl: additions[i].purl,
          new_scope: additions[i]&.scope
        ))
      end

      # make sure any leftover additions and removals get put back where they belong
      if additions.count != removals.count
        additions.drop(overlap).each do |addition|
          ret.push(addition)
        end

        removals.drop(overlap).each do |removal|
          ret.push(removal)
        end
      end
      ret
    end

    def apply_to_snapshot(snapshot:)
      # Group updates by manifest path
      manifest_changes = changes.collect.group_by(&:manifest_path)
      manifests = []

      # iterate over existing manifests
      snapshot.manifests.each do |manifest|
        deps = []
        to_update = (manifest_changes[manifest.path] || []).filter(&:update?).group_by(&:name)
        to_remove = (manifest_changes[manifest.path] || []).filter(&:removal?).group_by(&:name)
        to_add = (manifest_changes[manifest.path] || []).filter(&:addition?)

        manifest.dependencies.each do |dep|
          # find an applicable update if possible and apply it to this dep
          if update = (to_update[dep.name] || []).filter { |u| u.old_version == dep.version && u.scope == dep.scope }.first
            deps.push(Snapshots::Dependency.new(
              name: dep.name,
              version: update.new_version,
              scope: dep.scope
            ))
            next
          end

          # no update for this, make sure we're not supposed to remove it
          unless (to_remove[dep.name] || []).any? { |removal| removal.version == dep.version && removal.scope == dep.scope }
            deps.push(Snapshots::Dependency.new(
              name: dep.name,
              version: dep.version,
              scope: dep.scope
            ))
          end
        end

        # grab the net-new dependencies
        to_add.each do |addition|
          deps.push(Snapshots::Dependency.new(
            name: addition.name,
            version: addition.version,
            scope: addition.scope
          ))
        end

        unless deps.empty?
          manifests.push(Snapshots::Manifest.new(
            path: manifest.path,
            oid: manifest.oid,
            dependencies: deps
          ))
        end
      end # end of manifest additions and removals

      existing_manifests = Set.new(snapshot.manifests.map(&:path))
      manifests_with_additions = Set.new(changes.filter(&:addition?).map(&:manifest_path))

      (manifests_with_additions - existing_manifests).each do |new_manifest|
        deps = manifest_changes[new_manifest].filter(&:addition?).map { |addition|
          Snapshots::Dependency.new(
            name: addition.name,
            version: addition.version,
            scope: addition.scope
          )
        }
        manifests.push(Snapshots::Manifest.new(
          path: new_manifest,
          oid: nil,
          dependencies: deps
        ))
      end

      Snapshots::Snapshot.new(
        metadata: snapshot.metadata,
        github_repository_id: snapshot.github_repository_id,
        manifests: manifests,
        source: snapshot.source
      )
    end
  end
end
