# typed: true
# frozen_string_literal: true

module Elastomer

  # The SearchIndexManager is responsible for creating search indices on the
  # clusters, promoting search indices to the primary role, and deleting search
  # indices. The manager class encapsulates the rules and logic for creating
  # sliced indices and promoting slices to the primary role or the entire sliced
  # index to the primary role.
  module SearchIndexManager
    extend self
    include Kernel

    PRIMARY_CLEANUP_JOB_DELAY = Elastomer::Router::IndexMap::TTL + 1.minute

    # TODO gotta figure out naming and who is responsible for that ...

    # Compute a version SHA1 string for the :mappings and :settings of an
    # index. This version string will be stored in the index meta data. It is
    # useful for determining if the index settings are out of date and in need
    # of an update.
    #
    # opts - The options Hash
    #   :mappings   - index mappings Hash
    #   :settings   - index settings Hash
    #   :v          - optional version number to force a new version string
    #
    # Returns a SHA1 version String.
    def version(mappings:, settings:, v: 0)
      # add boilerplate settings if running in prod env
      settings = inject_es_prod_settings(settings, Rails.env.production?)

      # rubocop:disable GitHub/InsecureHashAlgorithm
      version = Digest::SHA1.hexdigest \
        MultiJson.dump(v: v, mappings: mappings, settings: filter_settings(settings))

      version.freeze
    end

    # Filter out index settings based on GitHub.es_skip_settings_fields
    def filter_settings(settings)
      return if settings.nil?

      return settings if GitHub.es_skip_settings_fields.empty?

      return settings unless settings.key?(:index)

      settings = settings.dup
      settings[:index] = settings[:index].except(*GitHub.es_skip_settings_fields)

      settings
    end

    def create_index(name:, cluster: "default", mappings: nil, settings: nil, metadata: nil,
                     index_class: nil, range: nil, postfix: Elastomer::Environment.postfix)

      index_class = Elastomer.env.lookup_index(name) if index_class.nil?

      slicer = index_class.slicer
      slicer.postfix = postfix
      slicer.fullname = name

      metadata = {} unless metadata.is_a?(Hash)
      mappings = index_class.mappings(cluster) || {} unless mappings.is_a?(Hash)
      settings = index_class.settings(cluster) || {} unless settings.is_a?(Hash)

      # add boilerplate settings if running in prod env
      settings = inject_es_prod_settings(settings, Rails.env.production?)

      # application defined metadata
      version = metadata["version"] || version(mappings: mappings, settings: settings)
      index_metadata = { "version": version }.merge(index_class.metadata || {})

      # ES8-COMPATIBILITY - add the index metadata to the mappings. Replace this once we upgrade to ES8.
      mappings = index_class.write_index_metadata(mappings, index_metadata, cluster)

      if index_class.sliced? && range
        each_slice(name, index_class, range) do |slice|
          _create_index(name: slice, cluster: cluster, mappings: mappings, settings: settings, metadata: metadata, version: version)
        end
      else
        _create_index(name: name, cluster: cluster, mappings: mappings, settings: settings, metadata: metadata, version: version)
      end
    end

    # Given a SearchIndexTemplateConfiguration instance and a slice name, create
    # a new search index for that particular slice. If an index slice already
    # exists a new one will still be created but with a higher slice version
    # number.
    #
    # template - a SearchIndexTemplateConfiguration instance
    # slice    - the String name of the slice (i.e. "2017-04" for audit logs)
    #
    # Returns the name of the newly created search index.
    def create_index_from_template(template:, slice:)
      slicer = template.slicer
      slicer.slice = slice
      slicer.slice_version = nil

      name = Elastomer.router.index_map.next_available_index_slice_name(slicer.fullname)

      metadata = {
        "read"    => true,
        "write"   => template.is_writable,
        "primary" => template.is_primary,
      }

      aliases = {}
      if template.is_primary
        aliases[slicer.index_alias] = {}

        slice_alias = slicer.slice_alias
        unless name == slice_alias
          aliases[slice_alias] = {}
        end
      end
      _create_index \
          name:     name,
          cluster:  template.cluster,
          metadata: metadata,
          aliases:  aliases,
          version:  template.version_sha

      # Busts the local cache of index configurations
      Elastomer.router.index_map.refresh

      name
    end

    # This methd will only create a new search index if a writable search index
    # created from the given `template` does not already exist. So if there is a
    # writable index for the template and slice, then that index name is
    # returned. But if there is not a writable index for the template and slice
    # then a new index is created.
    #
    # template - a SearchIndexTemplateConfiguration instance
    # slice    - the String name of the slice (i.e. "2017-04" for audit logs)
    #
    # Returns the name of the search index.
    def create_or_return_index_from_template(template:, slice:)
      name = writable_index_for(template: template, slice: slice)
      name = create_index_from_template(template: template, slice: slice) if name.nil?
      name
    end

    # Internal: Helper method that retrieves the first writable index for the
    # given index template and slice name. The search index must have the same
    # version number as the template and the given slice value.
    #
    # For audit logs, if the template is named "audit_log-3" and the slice value
    # is "2017-05" then the first writable index that matches "audit_log-3-2017-05-\d+"
    # will be returned.
    #
    # Returns a search index name as a String or `nil` if there are no writable
    # indices.
    def writable_index_for(template:, slice:)
      ary = Elastomer.router.index_map.writable(template.index_class, slice)
      return if ary.nil? || ary.empty?

      # find the index slice created from the template (the versions will match)
      index_config = ary.find { |ic| ic.index_version == template.version }
      return if index_config.nil?

      index_config.name
    end

    # Apply any mapping changes to the given index and update the index version.
    #
    # - If there are no changes to the mapping, this method will return early.
    # - If there are changes to the mapping, but they are not safe to be applied, this method will raise an
    #   Elastomer::Mappings::DestructiveMappingChangeError error.
    # - If the changes were applied successfully, this method will return true.
    sig { params(name: String, cluster: String, index_class: T.class_of(Elastomer::Index)).returns(T::Boolean) }
    def update_index_mapping(name:, cluster:, index_class:)
      index = index_class.new(name, cluster)

      unless index.mapping_diff.changes?
        return false
      end

      unless index.update_mapping_valid?
        raise Elastomer::Mappings::DestructiveMappingChangeError.new(name)
      end

      old_version = index.version
      generated_mapping = generate_mapping(cluster:, index_class:)

      # Elasticsearch 8+ does not support custom document types, so we need to update the mapping for the _doc type.
      # /index/_mapping/_doc
      response = index.put_mapping("_doc", generated_mapping.mapping)
      acknowledged = response["acknowledged"]

      tags = %W[search:ops action:update_mapping cluster:#{cluster} index:#{index.name}]
      if acknowledged
        index.update_config({ version: generated_mapping.version })
        GitHub.dogstats.event \
          "Search index mapping updated: #{name.inspect}",
          "Search index #{name.inspect} mapping updated on cluster #{cluster.inspect} from version #{old_version.inspect} to #{generated_mapping.version.inspect}",
          tags:
      else
        GitHub.dogstats.event \
          "Search index mapping update not acknowledged: #{name.inspect}",
          "Search index #{name.inspect} mapping update was not acknowledged on cluster #{cluster.inspect}",
          tags:
      end

      acknowledged
    end

    # Prepare an Elasticsearch mapping for a given index class and cluster. Encoded in the mapping is the version
    # of the index which is used to determine if the mapping needs to be updated. The version is a SHA1 hash of the
    # mappings and settings defined in the index class.
    #
    # Returns a Hash of the mapping.
    sig { params(cluster: String, index_class: T.class_of(Elastomer::Index)).returns(Elastomer::Mappings::GeneratedMapping) }
    def generate_mapping(cluster:, index_class:)
      mappings = index_class.mappings(cluster)
      settings = index_class.settings(cluster)
      settings = inject_es_prod_settings(settings, Rails.env.production?)
      new_version = version(mappings:, settings:)
      index_metadata = index_class.metadata || {}
      index_metadata["version"] = new_version

      # Encode the new index version into the mapping metadata.
      mapping = index_class.write_index_metadata(mappings, index_metadata, cluster)

      Elastomer::Mappings::GeneratedMapping.new(mapping:, settings:, version: new_version)
    end

    #
    #
    def open_index(name:, cluster: "default")
      client = Elastomer.router.client(cluster)
      index_class = Elastomer.env.lookup_index(name)

      if client.available?
        index = client.index(name)
        if index.exists?
          index.open
          GitHub.dogstats.event \
            "Search index opened: #{name.inspect}",
            "Search index #{name.inspect} opened on cluster #{cluster.inspect}",
            tags: %W[search:ops action:open cluster:#{cluster}]
        end
      end
    end

    #
    #
    def close_index(name:, cluster: "default", force: false)
      config = Elastomer.router.get_index_config(name)
      return false if !force && config && config.primary?

      client = Elastomer.router.client(cluster)
      index_class = Elastomer.env.lookup_index(name)

      unless config.nil?
        config.update!(read: false, write: false, primary: false)
        Elastomer.router.update_index_config(config)
      end

      if client.available?
        index = client.index(name)
        if index.exists?
          index.close
          GitHub.dogstats.event \
            "Search index closed: #{name.inspect}",
            "Search index #{name.inspect} closed on cluster #{cluster.inspect}",
            tags: %W[search:ops action:close cluster:#{cluster}]
        end
      end
    end

    sig { params(destination_index: Index).returns(T.nilable(Reindex)) }
    def create_reindex_job(destination_index)
      primary_index = Elastomer.router.primary(destination_index.class)
      if primary_index.nil? || primary_index.name == destination_index.name
        return nil
      end
      Elastomer::Reindex.new(primary_index.name, destination_index, destination_index.cluster_name)
    end

    #
    #
    sig { params(name: String).returns(T.nilable(RepairJob)) }
    def create_repair_job(name)
      job = Elastomer.env.lookup_repair_job(name)

      if job.is_a?(RepairCodeSearchIndexJob)
        return unless GitHub.use_elastomer_code_search?
      end

      job.new(name) if job < Elastomer::RepairJob
    rescue Elastomer::Error, ElastomerClient::Error
      nil
    end

    #
    #
    def delete_repair_job(name)
      repair_job = create_repair_job(name)
      repair_job.reset! if repair_job
    end

    #
    #
    def delete_index(name:, cluster: "default", index_class: nil, force: false, postfix: Elastomer::Environment.postfix)
      index_class = Elastomer.env.lookup_index(name) if index_class.nil?

      slicer = index_class.slicer
      slicer.postfix = postfix
      slicer.fullname = name

      if index_class.sliced? && slicer.slice.nil?
        all_index_slices(name) { |cfg| _delete_index(cfg.name, cfg.cluster, force) }
      else
        _delete_index(name, cluster, force)
      end
    end

    # Public: Make the given index the primary for the index class. This will
    # be the index that is used to serve queries.
    #
    # name - The index to make primary
    #
    # Returns `nil`
    def promote_index_to_primary(name:, index_class: nil, postfix: Elastomer::Environment.postfix)
      router      = Elastomer.router
      index_map   = router.index_map
      index_class = Elastomer.env.lookup_index(name) if index_class.nil?
      kind        = index_class.logical_index_name

      slicer          = index_class.slicer
      slicer.postfix  = postfix
      slicer.fullname = name

      # operate on all slices for the index
      cmds = if index_class.sliced? && slicer.slice.nil?
        primaries = index_map.primary(kind, "*")
        version   = primaries.map(&:index_version).uniq.min
        primary   = "#{slicer.index}-#{version}"
        return if primary == name

        candidates = index_map.all_index_slices(name)
        if candidates.nil? || candidates.empty?
          raise ArgumentError, "index #{name.inspect} does not exist in the search index router"
        else
          candidates.each do |cfg|
            next if cfg.exists?
            raise ArgumentError, "index #{cfg.name.inspect} does not exist on the search cluster"
          end
        end

        build_primary_promotion_cmds(primaries, candidates, index_class)
      else
        primaries = index_map.primaries(kind, slicer.slice)

        # Return if list of primary indexes consists of only the candidate
        return if primaries.size == 1 && primaries.first.name == name
        # Remove the candidate from the list of primaries to avoid it being demoted
        primaries.reject! { |index| index.name == name }

        candidate = router.get_index_config(name)
        if candidate.nil?
          raise ArgumentError, "index #{name.inspect} does not exist in the search index router"
        elsif !candidate.exists?
          raise ArgumentError, "index #{name.inspect} does not exist on the search cluster"
        end

        build_primary_promotion_cmds(primaries, candidate, index_class)
      end

      # Check to see if we're changing clusters for this index. If so, we need to delay the alias updates on the old
      # cluster so that the 2 minute TTL of the DB cache can expire. Otherwise, search queries will fail.
      update_aliases_cluster_names = cmds.select { |cmd| cmd.first == :update_aliases }.map(&:second).map(&:first)
      if update_aliases_cluster_names.uniq.count == 2
        old_update_aliases_cmds, cmds = cmds.partition { |cmd| cmd.first == :update_aliases && cmd.second.second.first.dig(:remove) }
        Elastomer::SearchIndexPrimaryCleanupJob.set(wait: PRIMARY_CLEANUP_JOB_DELAY).perform_later(old_update_aliases_cmds)
      end

      cmds.each { |method, args| T.unsafe(self).send(method, *args) }

      cluster_name = !candidate.nil? ? candidate.cluster : candidates.first.cluster

      GitHub.dogstats.event \
        "Search index promoted: #{name.inspect}",
        "Search index #{name.inspect} was promoted to the primary role and is now serving production queries for #{kind.inspect} search indices.",
        tags: %W[search:ops action:primary cluster:#{cluster_name}]

      nil
    end

    #
    #
    def create_template(name:, cluster: "default", mappings: nil, settings: nil, primary: false,
                        index_class: nil, postfix: Elastomer::Environment.postfix)

      client   = ::Elastomer.router.client(cluster)
      template = client.template(name)
      return if template.exists?

      name_adjust = name.sub(/_template\z/, "")
      index_class = ::Elastomer.env.lookup_index(name_adjust) if index_class.nil?

      slicer = index_class.slicer
      slicer.postfix = postfix
      slicer.fullname = name_adjust

      mappings = index_class.mappings(cluster) || {} unless mappings.is_a?(Hash)
      settings = index_class.settings(cluster) || {} unless settings.is_a?(Hash)

      # add boilerplate settings if running in prod env
      settings = inject_es_prod_settings(settings, Rails.env.production?)

      # application defined metadata
      index_metadata = index_class.metadata || {}
      index_metadata["version"] = version = version(mappings: mappings, settings: settings)

      # ES8-COMPATIBILITY - add the index metadata to the mappings. Replace this once we upgrade to ES8.
      mappings = index_class.write_index_metadata(mappings, index_metadata, cluster)
      template_glob = name_adjust =~ /test\z/i ? "#{name_adjust}*" : "#{name_adjust}-*"

      body = {
        order:    0,
        mappings: mappings,
        settings: settings,
      }
      body[:aliases] = { slicer.index_alias => {} } if primary

      if Elastomer.router.cluster_running_version_8_plus?(cluster)
        body[:index_patterns] = [template_glob]
      else
        body[:template] = template_glob
      end

      response = template.create(body)

      GitHub.dogstats.event \
        "Search index template created: #{name.inspect}",
        "Search index template #{name.inspect} created on cluster #{cluster.inspect} with version #{version.inspect}",
        tags: %W[search:ops action:create cluster:#{cluster}]

      response
    end

    #
    #
    def delete_template(name:, cluster: "default", force: false,
                        index_class: nil, postfix: Elastomer::Environment.postfix)

      client   = ::Elastomer.router.client(cluster)
      template = client.template(name)
      return unless template.exists?

      name_adjust = name.sub(/_template\z/, "")
      index_class = ::Elastomer.env.lookup_index(name_adjust) if index_class.nil?

      slicer = index_class.slicer
      slicer.postfix = postfix
      slicer.fullname = name_adjust

      hash = template.get
      aliases = hash.dig(name, "aliases")
      primary = aliases && aliases.keys.include?(slicer.index_alias)

      return if primary && !force

      begin
        response = template.delete
      rescue ElastomerClient::Client::TimeoutError => err
        Failbot.report(err, "db.elasticsearch.cluster.name": cluster)
      end

      GitHub.dogstats.event \
        "Search index template deleted: #{name.inspect}",
        "Search index template #{name.inspect} deleted from cluster #{cluster.inspect}",
        tags: %W[search:ops action:delete cluster:#{cluster}]

      response
    end

    # Internal: Build the list of commands needed to demote the current
    # `primaries` and promote the `candidates` to the primary role. The
    # `index_class` is included so this method can figure out all the required
    # aliases to transfer to the candidate index(es).
    #
    # primaries   - IndexConfig for the current primary (single or Array)
    # candidates  - IndexConfig for the candidate (single or Array)
    # index_class - the Index class for all the primaries and candidates
    #
    # Returns an array of [method_name, args] tuples.
    def build_primary_promotion_cmds(primaries, candidates, index_class)
      primaries  = Array(primaries)
      candidates = Array(candidates)
      alias_cmds = Hash.new { |h, k| h[k] = [] }
      cmds = []

      # 1 - add aliases to the candidate slices
      candidates.each do |cfg|
        cfg.aliases.each do |str|
          alias_cmds[cfg.cluster] << { add: { index: cfg.name, alias: str } }
        end
      end

      # 2 - remove aliases from the current primary slices
      primaries.dup.each do |cfg|
        # Skip if the config for the primary doesn't exist anymore
        # This can be the case in GHES scenarios when a DR cluster is failed over
        next unless Elastomer.router.clusters.include?(cfg.cluster)

        # Skip if the index doesn't exist
        next unless cfg.exists?
        aliases = cfg.aliases
        if aliases.include?(cfg.name)
          cmds << [:_delete_index, [cfg.name, cfg.cluster, true]]
          primaries.delete(cfg)
        else
          aliases.each do |str|
            alias_cmds[cfg.cluster] << { remove: { index: cfg.name, alias: str } }
          end
        end
      end

      alias_cmds = alias_cmds.to_a

      cmds << [:update_aliases, alias_cmds.first]
      cmds << [:update_index_config, [candidates, { read: true, write: true, primary: true }]]
      cmds << [:update_index_config, [primaries, { primary: false }]] unless primaries.empty?

      if alias_cmds.length == 2
        cmds << [:update_aliases, alias_cmds.last]

      elsif alias_cmds.length > 2
        raise ArgumentError, "too many search clusters: #{alias_cmds.inspect}"
      end

      cmds
    end

    def reconcile_aliases(cluster, index)
      aliases = index.get_aliases

      if index.class.respond_to?(:aliases) && index.class.aliases.length > aliases.length
        aliases_to_add = index.class.aliases - aliases
        alias_commands = aliases_to_add.map do |alias_to_add|
          {
            add: {
              index: index.name,
              alias: alias_to_add
            }
          }
        end
        update_aliases(cluster, alias_commands)
      end
    end

    # Internal: Execute the various alias `actions` on the given Elasticsearch
    # `cluster`.
    #
    # cluster - name of the Elasticsearch cluster
    # actions - Array of alias actions
    #
    # see https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html
    #
    # Returns the result from the Elastomer method call
    def update_aliases(cluster, actions)
      client = Elastomer.router.client(cluster)
      client.cluster.update_aliases(actions)
    end

    # Internal: Update the given `index_configs` using the `settings` hash.
    #
    # index_configs - IndexConfig to update (single or Array)
    # settings      - Hash of index config settings to update
    #
    def update_index_config(index_configs, settings)
      Array(index_configs).each do |cfg|
        cfg.update!(settings)
        Elastomer.router.update_index_config(cfg)
      end
    end

    # Internal: Given a base index name and a range of slices, this method will
    # generate full index names and yield them in turn to the given block.
    #
    # name        - base name for the index (audit_log-12)
    # index_class - an Elastomer::Index class
    # range       - a Range denoting the first and last slices
    #
    # Returns `nil`
    def each_slice(name, index_class, range)
      return unless index_class.sliced?

      slicer = index_class.slicer
      slicer.fullname = name
      slicer.slice_version = 1 if slicer.slice_version.nil?

      slicer.slice_range(range.first, range.last) do |slice|
        slicer.slice = slice
        yield slicer.fullname
      end

      nil
    end

    # Internal: Iterate the given block of code for the index configs of all
    # slices of an index. The index name and version are required to select all
    # the slices.
    #
    # name - The index name with version number
    #
    # Returns `nil` or an array of index settings.
    def all_index_slices(name, &block)
      index_map = Elastomer.router.index_map
      ary = index_map.all_index_slices(name)
      ary.each(&block) unless ary.nil?
    end

    # Internal: Creates an Elasticsearch index on a search cluster and adds an
    # entry to the MySQL index configuration table (see
    # Elastomer::Router:MysqlStore).
    #
    # name     - index name as a String
    # cluster  - cluster name as a String
    # mappings - Hash of index mappings
    # settings - Hash of index settings
    # metadata - Hash with metadata to store in the index config
    # aliases  - Hash of index aliases
    # version  - index version SHA
    #
    # Returns the Elasticsearch response Hash.
    def _create_index(name:, cluster:, metadata:, version:, mappings: {}, settings: {}, aliases: {})
      client = Elastomer.router.client(cluster)
      index  = client.index(name)
      exists = index.exists?
      if !exists
        # create the index in Elasticsearch and wait for the cluster health to report green
        response = index.create(mappings: mappings, settings: settings, aliases: aliases)
        client.cluster.health \
          index: name,
          wait_for_status: "green",
          timeout: "20s",
          read_timeout: 9
      end

      # now update our IndexConfig in the MySQL table so we know about this new index
      if Elastomer.router.get_index_config(name).nil?
        config = Elastomer::Router::IndexConfig.new \
            name:    name,
            cluster: cluster,
            version: version

        config.update!(metadata)
        Elastomer.router.update_index_config(config)
      else
        return if exists
      end

      GitHub.dogstats.event \
        "Search index created: #{name.inspect}",
        "Search index #{name.inspect} created on cluster #{cluster.inspect} with version #{version.inspect}",
        tags: %W[search:ops action:create cluster:#{cluster}]

      response
    end

    # Internal: Delete a single Elasticsearch index from a cluster and remove
    # the MySQL index configuration entry (see Elastomer::Router:MysqlStore).
    #
    # name     - index name as a String
    # cluster  - cluster name as a String
    # force    - boolean used to force index deletion
    #
    # Returns the Elasticsearch response Hash.
    def _delete_index(name, cluster, force)
      config = Elastomer.router.get_index_config(name)
      return false if !force && config && config.primary?

      client = Elastomer.router.client(cluster)
      Elastomer.router.remove_index_config(name)

      if client.available?
        index = client.index(name)
        if index.exists?
          delete_repair_job(name)
          begin
            index.delete
          rescue ElastomerClient::Client::TimeoutError => err
            Failbot.report(err, "db.elasticsearch.cluster.name": cluster)
          end
          GitHub.dogstats.event \
            "Search index deleted: #{name.inspect}",
            "Search index #{name.inspect} deleted from cluster #{cluster.inspect}",
            tags: %W[search:ops action:delete cluster:#{cluster}]
        end
      end
    end

    # Injects index-level settings into base settings hash only in prod env, for ES5+ clusters
    #
    # settings          -       base settings hash
    # prod_env          -       boolean value, equal to "Rails.env.production?"
    def inject_es_prod_settings(settings, prod_env)
      return settings if !prod_env

      settings[:index] = {} if !settings.key?(:index)
      if !settings.dig(:index, :translog)
        settings[:index][:translog] = {
          durability: "async",
          sync_interval: "5s",
        }
      end

      settings
    end
  end
end
