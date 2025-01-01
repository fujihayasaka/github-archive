# typed: true
# frozen_string_literal: true

module Elastomer
  class App
    require "optparse"

    # Convenience method for creating and running an Elastomer::App.
    #
    # args - The Array of command line arguments.
    #
    # Examples
    #
    #   Elastomer::App.run(ARGV)
    #
    # Returns the Elastomer::App instance.
    def self.run(args)
      new.parse_options(args).run
    end

    # Used for cisetup and parallel test runners
    attr_accessor :num_indices

    # Controls purging of non-primary indices
    attr_accessor :purge_non_primary
    alias :purge_non_primary? :purge_non_primary

    # Controls whether to promote index to primary
    attr_accessor :primary_cluster
    alias :primary_cluster? :primary_cluster

    # Controls rebuilding of indices created with
    # a different ES major version
    attr_accessor :check_es_index_version
    alias :check_es_index_version? :check_es_index_version

    # The current Rails environment
    attr_reader :env

    # Operate on a specific cluster
    attr_reader :cluster

    # Create a new Elastomer::App for running operations on Elasticsearch
    # indices from the command line.
    #
    # opts - The options Hash
    #   :num_indices            - the number of test indices to create
    #   :purge_non_primary      - set to `true` to purge older indices
    #   :cluster                - limit operations to the specified cluster only
    #   :primary_cluster        - set to `false` to not promote the newly created
    #                             indices to primary. Used when setting up indices
    #                             on DR environments in enterprise.
    #   :check_es_index_version - set to `true` to rebuild indices created
    #                             by a previous ES major version
    def initialize(opts = {})
      @num_indices            = opts.fetch(:num_indices, 0)
      @audit                  = opts.fetch(:audit, GitHub.audit)
      @purge_non_primary      = opts.fetch(:purge, false)
      # With multiple clusters, find one that matches the global GitHub.elasticsearch_url, which may be overridden by env vars
      @cluster                = opts.fetch(:cluster, GitHub.es_clusters.find { |_, v| v[:url] == GitHub.elasticsearch_url }&.first)
      @primary_cluster        = opts.fetch(:primary_cluster, true)
      @check_es_index_version = opts.fetch(:check_es_index_version, false)
      @env                    = opts.fetch(:env, Rails.env).to_s

      unless %w[development test production].include? @env
        raise "Unknown environment: #{@env.inspect}"
      end
    end

    # Returns `true` if the current environment is "test"
    def test?
      @env == "test"
    end

    # Returns `true` if the current environment is "development"
    def development?
      @env == "development"
    end

    # Returns `true` if the current environment is "production"
    def production?
      @env == "production"
    end

    # Returns `true` if this is an enterprise environment
    def enterprise?
      GitHub.enterprise?
    end

    # Parse the command line options from the array of 'args'. The options will
    # be stored in the `options` hash. If the command line arguments are
    # incorrect then a help message will be printed to the terminal and the
    # program will abort.
    #
    # args - The Array of command line arguments.
    #
    # Examples
    #
    #   parse_options(ARGV)
    #   #=> self
    #
    # Returns this App instance.
    def parse_options(args)
      args = args.dup

      opt = OptionParser.new
      opt.banner = "Usage: elastomer <command> [options]"

      opt.separator ""
      opt.separator <<-MSG
      The elastomer script encapsulates some common actions for working with indices
      in ElasticSearch. With this tool you can create and delete indices, and you can
      load data into indices.
      MSG

      opt.separator ""
      opt.separator "Commands:"
      opt.separator "    bootstrap\t\t\t     Create and load modified indices."
      opt.separator "    reset\t\t\t     Delete, recreate, and load all indices."
      opt.separator "    repair\t\t\t     Reconcile indices with the database."
      opt.separator "    setup\t\t\t     Create indices."
      opt.separator "    upgrade\t\t\t     Upgrade and load new indices."
      opt.separator "    backfill <topic>\t\t    Backfill Kafka topic."

      if test?
        opt.separator "    cisetup\t\t\t     Delete all indexes and create all test indices."
      end

      opt.separator ""
      opt.separator "Advanced Options:"
      opt.on("--purge", false, "Purge older indices.") { |v| self.purge_non_primary = !!v }

      if test?
        opt.on("--num-indices [number]",  Integer, "Create N versions of each index, numbered 1..N.") { |v| self.num_indices = v }
      end

      opt.separator ""
      opt.separator "Common options:"

      opt.on_tail("-h", "--help", "Show this message") do
        puts opt
        exit
      end

      opt.parse!(args)
      @command = args.first
      @args = args[1..args.length]

      unless %w[bootstrap reset repair setup upgrade backfill cisetup].include? @command
        puts opt
        abort
      end

      self
    end

    # The client used for communicating with Elasticsearch.
    def client
      return @client if defined?(@client) && @client

      ::Elastomer.config.read_timeout = 150.seconds.to_i
      @client = Elastomer.client
    end

    # Wait for the cluster status to become green.
    def wait_for_status(status = "green")
      client.cluster.health \
        wait_for_status: status,
        timeout: "120s"
    end

    # Run the user specified command.
    #
    # Returns this App instance.
    def run
      if production? && !enterprise?
        STDERR.puts \
            "The elastomer script cannot be used in production.\n" +
            "This script is only for GitHub Enterprise production environments."
        abort
      end

      # Abort if we do not have access to Elasticsearch
      unless client.available?
        STDERR.puts \
            "Could not connect to the Elasticsearch server at #{client.url.inspect}.\n" +
            "Please ensure that the server is running and accepting connections."
        @command == "bootstrap" ? exit : abort
      end

      self.send(@command.to_sym)
    end

    # Implementation of the setup command. This will create indices necessary
    # for the application to run if they do not already exist. If a primary
    # index already exists then no action is taken even if that primary index is
    # out of date.
    #
    # The `bootstrap` (for development) and `upgrade` (for Enterprise) tasks
    # should be used to upgrade indices as needed.
    #
    # Returns self.
    def setup
      refresh!
      enable_code_search

      create_audit_log
      wait_for_status("yellow")

      each_index_class do |index_class|
        if primary_cluster?
          primary_index(index_class)
        else
          index_name = latest_index_name(index_class)
          index = index_class.new(index_name, cluster)
          unless index.exists?
            puts "Creating index #{index_name.inspect}."
            index.create
          end
          index.update_config(read: true, write: true)
          load_data(index)
        end
        purge(index_class) if purge_non_primary?
      end
    end

    # Implementation of the bootstrap command. This will create indices and
    # populate them with data. If an index exists but needs updating, then this
    # command will create a new index and make it the primary.
    #
    # Returns self.
    def bootstrap
      refresh!
      enable_code_search

      create_audit_log
      wait_for_status("yellow")

      each_index_class do |index_class|
        index = current_index(index_class)

        unless primary_index?(index)
          load_data(index)
          promote_to_primary(index)
        end

        purge(index_class) if purge_non_primary?
      end
    end

    # Implementation of the reset command. This deletes all indices corresponding
    # to an Elastomer Index, recreates them, and loads data into them using the
    # load_data class method for each individual index class.
    #
    # Returns self.
    def reset
      refresh!
      enable_code_search

      audit_log = create_audit_log
      wait_for_status("yellow")
      audit_log.reset_index unless audit_log.nil?

      each_index_class do |index_class|
        purge(index_class, :purge_primary)
        index = primary_index(index_class)
        load_data(index)
      end
    end

    # Implementation of the repair command. This will iterate over each index
    # and reconcile all the documents in the index with their canonical
    # representations from the database (or the file servers if we're talking
    # about code-search). If an index does not exist then it will be created
    # and populated with documents.
    #
    # This command runs each repair task in series. So it might take a while
    # to complete depending on the total size of the search indices.
    #
    # Returns self.
    def repair
      refresh!
      enable_code_search

      each_index_class do |index_class|
        index = primary_index(index_class)
        load_data(index)
        purge(index_class) if purge_non_primary?
      end
    end
    alias :populate :repair

    # Implementation of the upgrade command. This will create new indices for
    # any that are out of date and then populate those newly created indices
    # with data.
    #
    # The new indices are created immediately, but the backfill tasks run in
    # series for the newly created indices. So it might take a while to complete
    # depending on the total size of the search indices.
    #
    # The primary difference between this command and the `bootstrap` command is
    # when the index is created vs when it is filled with data and promote to
    # primary. This command will create all the indices first and make them
    # writable. Then each newly created index is backfilled and then promoted to
    # the primary role.
    #
    # Returns self.
    def upgrade
      refresh!
      enable_code_search

      create_audit_log
      wait_for_status("yellow")

      indices = []

      # create the indices immediately and make them writable (except for code search)
      each_index_class do |index_class|
        index = current_index(index_class)
        index.update_config(read: true, write: true) unless Indexes::CodeSearch == index_class
        indices << index
      end

      # generate the list of freshly created indices
      fresh_indices = indices.select { |index| fresh_index?(index) }

      # iterate over the indices and backfill and promote the non-primary
      # indices (this will make the code search index writable)
      indices.each do |index|
        next if !cluster.nil? && index.cluster_name != cluster
        load_data(index, run_jobs: true) if fresh_indices.include?(index)
        promote_to_primary(index) if primary_cluster?
        purge(index.class) if purge_non_primary?
      end

      self
    end

    # Delete all indexes in the cluster and create N copies of each index for CI.
    def cisetup
      fail "tried to cisetup without RAILS_ENV=test" if !test?

      STDERR.puts "Preparing Elasticsearch #{client.version} for #{num_indices} indices"

      # Delete all indexes so that the tests start with a blank slate This will
      # make CI take slightly longer, but prevents index pollution from previous
      # test runs from interfering with this CI run.
      make_blank_index_deleteable # Handle read-only "blank" index that was inserted as a logic bomb

      enable_wildcard_deletion

      Elastomer.client.delete("/_all")

      counter = 0
      alias_cmds = []
      start = Time.now

      create_audit_log
      wait_for_status("yellow")

      postfix = Elastomer::Environment.postfix
      cluster_name = cluster || Elastomer.router.clusters.first

      each_index_class do |index_class|
        version = Elastomer::SearchIndexManager.version(
          mappings: index_class.mappings(cluster_name),
          settings: index_class.settings(cluster_name),
          v: 8,
        )

        (num_indices + 1).times do |num|
          counter += 1
          suffix = (num == 0 ? nil : num)
          Elastomer::Environment.postfix = "#{postfix}#{suffix}"
          index = index_class.new
          index.create(metadata: { "version" => version })
          alias_cmds.concat(cisetup_index_alias_cmds(index_class))
        end
      end

      # Reset the index postfix
      Elastomer::Environment.postfix = postfix

      client.cluster.update_aliases(alias_cmds) unless alias_cmds.empty?
      wait_for_status("yellow")
      STDERR.puts "Prepared #{counter} Elasticsearch indices in #{Time.now - start}s"
    end

    # Internal: Return a primary index for the given `index_class`. This method
    # will create the index if a primary index cannot be found for the class.
    # This primary index _can_ be out of date with the version from the index
    # class.
    #
    # index_class - The Index to create.
    #
    # Returns the primary index instance.
    def primary_index(index_class)
      name  = primary_index_name(index_class)
      index = index_class.new(name, cluster)

      unless index.exists?
        puts "Creating index #{name.inspect}."
        index.create
        promote_to_primary(index)
      end

      index
    end

    # Internal: Return an up-to-date index for the given `index_class`. This
    # method will create the index if an up-to-date index cannot be found for
    # the class. This index will not necessarily be the primary index for the
    # class.
    #
    # index_class - The Index to create.
    #
    # Returns the up-to-date index instance.
    def current_index(index_class)
      name  = current_index_name(index_class)
      index = index_class.new(name, cluster)

      unless index.exists?
        puts "Creating index #{name.inspect}."
        index.create
      end

      index
    end

    # Internal: Promote the given `index` to the primary role for the Index
    # type.
    #
    # index - The index instance to promote to the primary role
    #
    # Returns the index passed in
    def promote_to_primary(index)
      current_primary = Elastomer.router.primary(index.class)

      if current_primary && current_primary.name == index.name
        Elastomer::SearchIndexManager.reconcile_aliases(current_primary.cluster, index)
        puts "Primary index is #{index.name.inspect}."
        return index
      end

      Elastomer::SearchIndexManager.promote_index_to_primary(name: index.name)

      if current_primary
        puts "Primary changed from #{current_primary.name.inspect} to #{index.name.inspect}."
      else
        puts "New primary index #{index.name.inspect}."
      end

      index
    end

    # Internal: Returns `true` if the index has been created in the past
    # 60 minutes. This is an index we want to run a repair job on.
    #
    # index - The index to check for freshness
    #
    # Returns `true` or `false`
    def fresh_index?(index)
      return false unless index.creation_date
      (Time.now - index.creation_date) < 60.minutes
    end

    # Internal: Returns true if the given `index` is the current primary index
    # for its index class type. Returns false if this is not the case.
    #
    # index - The index instance to check for "primariness"
    #
    # Returns `true` or `false`
    def primary_index?(index)
      index.name == primary_index_name(index.class)
    end

    # Internal: Gets the name of the primary index for the given `index_class`.
    # This index might not exist yet.
    #
    # index_class - The Index class
    #
    # Returns the primary index name as a string.
    def primary_index_name(index_class)
      primary = Elastomer.router.primary(index_class)
      if primary
        primary.name
      else
        next_available_index_name(index_class)
      end
    end

    # Internal: Gets the name of the lastest index for the given `index_class`.
    # This index might not exist yet.
    #
    # index_class - The Index class
    #
    # Returns the latest index name as a string.
    def latest_index_name(index_class)
      latest_index = Elastomer.router.index_map.fetch(index_class)
        .select { |i| cluster.nil? ? true : i.cluster == cluster }
        .sort { |a, b| b.index.creation_date <=> a.index.creation_date }.first

      if latest_index
        latest_index.name
      else
        next_available_index_name(index_class)
      end
    end

    # Internal: Gets the name of the current index for the given `index_class`.
    # An index is current if the "version" of the index matches the "version"
    # from the `index_class` and also if the index was created with the same
    # major ES version. The named index might not exist yet.
    #
    # index_class - The Index class
    #
    # Returns the current index name as a string.
    def current_index_name(index_class)
      name = if primary_cluster?
        primary_index_name(index_class)
      else
        latest_index_name(index_class)
      end

      config = Elastomer.router.get_index_config(name)
      cluster_name = cluster || Elastomer.router.clusters.first

      index_version = Elastomer::SearchIndexManager.version \
          mappings:   index_class.mappings(cluster_name),
          settings:   index_class.settings(cluster_name)

      same_config_version = config.nil? || config.version == index_version
      upgraded_version = check_es_index_version? && rebuild_upgraded_version?(name)

      if !same_config_version || upgraded_version
        next_available_index_name(index_class)
      else
        name
      end
    end

    # Internal: checks if the given index needs to be
    # rebuilt because it has been created with a
    # previous version of ES.
    #
    # name - index name
    #
    # Returns whether or not the index needs to rebuilt
    def rebuild_upgraded_version?(name)
      index = Elastomer.client.index(name)
      cluster_name = cluster || Elastomer.router.clusters.first

      return false unless index.exists?

      begin
        settings = index.settings(cluster_name)
      rescue ElastomerClient::Client::IndexNotFoundError
        return false
      end

      version = settings.dig(name, "settings", "index", "version")

      return false if version.nil?

      # upgraded is only present when the index has been created
      # by a previous version of ES
      upgraded = version["upgraded"]

      return false if upgraded.nil?

      created = version["created"]

      # Only compare the major version
      upgraded[0] != created[0]
    end

    # Internal: Gets the next available index name as a string.
    #
    # index_class - The Index class to get a name for
    #
    # Returns the index name as a string.
    def next_available_index_name(index_class)
      Elastomer.router.index_map.next_available_index_name(index_class)
    end

    # Internal: This beauty of a method iterates over each index for the
    # particular `index_class` and deletes those that are _not_ the primary
    # index. If you set the `purge_primary` flag to true, then the primary
    # index will be deleted as well.
    #
    # index_class   - The Index class to purge from the search cluster
    # purge_primary - Boolean used to forcibly delete the primary index
    #
    # Returns this app instance.
    def purge(index_class, purge_primary = false)
      kind = index_class.logical_index_name
      indices = Elastomer.router.index_map.fetch(kind)
      return self if indices.blank?

      primary = Elastomer.router.primary(index_class)
      primary = primary ? primary.name : nil

      indices.each do |config|
        next if (primary == config.name) && !purge_primary

        next if !cluster.nil? && config.cluster != cluster

        begin
          puts "Deleting existing index #{config.name.inspect}."
          config.index.delete
        rescue ElastomerClient::Client::IndexNotFoundError
          nil
        rescue ElastomerClient::Client::TimeoutError, StandardError => boom # rubocop:todo Lint/GenericRescue
          puts "Error deleting index #{config.name.inspect}: #{boom.message}"
        end
      end

      self
    end

    # Internal: Refresh the internal mappings for the index-to-cluster router.
    def refresh!
      reconcile!
      Elastomer.router.refresh
      self
    end

    # Internal: Reconcile the index config table with the real indices found in
    # the Elasticsearch cluster(s).
    def reconcile!
      Elastomer.router.index_map.reconcile(override: false)

      indices = Elastomer::Router::ElasticsearchIterator.map(&:name)
      store   = Elastomer::Router::MysqlStore.new

      store.each do |config|
        next if indices.include? config.name
        store.delete_config config.name
      end

      self
    end

    # Internal: Given an index, look up the repair job for the index and then
    # load data into the index via the repair job. If a repair job does not
    # exist for the index, then this method does nothing and returns.
    #
    # index - The Index to populate with data
    #
    # Returns nil
    def load_data(index, run_jobs = false)
      return if test?

      job_class = Elastomer.env.lookup_repair_job(index.class)

      if job_class.to_s.include?("RepairCodeSearchIndexJob")
        return unless GitHub.use_elastomer_code_search?
      end

      job = job_class.new(index.name)

      STDOUT.puts "Loading documents into #{index.name.inspect} with #{GitHub.es_default_worker_count} workers."

      job.reset! if job.exists?
      job.enable

      if run_jobs
        job.start(GitHub.es_default_worker_count)

        until job.finished? || job.paused? || job.disabled?
          sleep(1)
        end
      else
        job.start(0)

        until job.finished? || job.paused? || job.disabled?
          STDOUT.write "."
          job.repair!
          job = job_class.new(index.name)
        end
      end

      STDOUT.puts "Finished loading documents into #{index.name.inspect}"

    rescue StandardError => boom # rubocop:todo Lint/GenericRescue
      return if boom.is_a?(Elastomer::Error) && boom.message.start_with?("GitHub::Jobs::")

      if boom.message.start_with?("Could not map")
        STDOUT.puts "Skipping document loading for the #{index.name.inspect} index."
        STDOUT.puts "-- #{boom.message.strip}"
      else
        STDERR.puts "\n\tERROR: #{boom.message.strip} (#{boom.class})"
        STDERR.puts "\tFailed to load documents into #{index.name.inspect} index.\n"
      end
    end

    # Internal: Enable indexing and searching of the code-search index.
    #
    # Returns self.
    def enable_code_search
      cs = Search::ClusterStatus.new
      cs.enable_code_search
      cs.enable_code_search_indexing
      self
    end

    # Internal: Returns an Array of index alias actions to be applied to the
    # search cluster for this particular index class. This Array can be empty.
    def cisetup_index_alias_cmds(index_class)
      return [] unless index_class.respond_to?(:aliases)

      index_name = index_class.index_name
      alias_cmds = index_class.aliases.map do |alias_name|
        next if index_name == alias_name
        { add: { index: index_name, alias: alias_name } }
      end
      alias_cmds.compact
    end

    # Internal: Recreates the audit log template.
    #
    # Returns the audit log index.
    def create_audit_log
      cleanup_audit_log_templates

      audit_logs_cluster = if cluster.nil?
        GitHub.es_audit_log_cluster
      else
        cluster
      end
      template = if test?
        SearchIndexTemplateConfiguration.find_by(fullname: Elastomer::Indexes::AuditLog.index_name)
      elsif primary_cluster?
        Elastomer.router.primary_template(Elastomer::Indexes::AuditLog, audit_logs_cluster)
      else
        Elastomer.router.writable_templates(Elastomer::Indexes::AuditLog, audit_logs_cluster).first
      end

      if template.nil?
        name = next_available_template_name(Elastomer::Indexes::AuditLog)
        template = SearchIndexTemplateConfiguration.new \
            fullname:    name,
            cluster:     audit_logs_cluster,
            is_writable: true,
            is_primary:  !test? && primary_cluster?  # we do not want the template to be primary in the test environment

        if template.exists?
          puts "Deleting audit log template #{template.fullname}."
          template.delete_template(force: true)
        end

        puts "Creating audit log template #{template.fullname}." unless template.exists?
        template.save!

      elsif !template.current?
        if template.exists?
          puts "Deleting audit log template #{template.fullname}."
          template.delete_template(force: true)
        end

        puts "Creating audit log template #{template.fullname}."
        template.is_writable = true
        template.is_primary  = !test? && primary_cluster?
        template.create_template
        template.save!
      end

      es_audit_logger
    end

    def next_available_template_name(index_class)
      name = Elastomer.router.next_available_template_name(index_class)
      name = name.sub(/-\d+\z/, "") if test?  # prune the version number in the test environment
      name
    end

    def cleanup_audit_log_templates
      name = test? ? "audit_log-test_template" : "audit_log_template"
      template = SearchIndexTemplateConfiguration.find_by(fullname: name)

      if template
        puts "Deleting audit log template #{template.fullname}."
        template.delete_template(force: true)
        template.destroy
      else
        template = Elastomer.client.template(name)
        if template.exists?
          puts "Deleting audit log template #{template.name}."
          template.delete
        end
      end
    end

    # Internal: Search for the ES audit log.
    #
    # Returns the ES logger.
    def es_audit_logger
      if @audit.logger.is_a?(Audit::Multi::Logger)
        @audit.logger.loggers.detect do |logger|
          logger.respond_to?(:create_template) && logger.respond_to?(:drop_template)
        end
      else
        @audit.logger
      end
    end

    # Internal: Iterate over each index class and yield that class to the given
    # block. The indices are presented in a specific order with the Users and
    # Repos indices appearing first and the CodeSearch index appearing last.
    # This is used on GitHub Enterprise to ensure indices are updated in the
    # most favorable order.
    #
    # Returns self.
    def each_index_class
      specials = [
        Indexes::CodeSearch,
        Indexes::Repos,
        Indexes::Projects,
        Indexes::Users,
        Indexes::AuditLog,
        Indexes::PullRequests,
        Indexes::Issues,
        Indexes::IssuesSemantic,
        Indexes::Commits,
        Indexes::WorkflowRuns
      ]

      indices = Elastomer.env.indices - specials

      indices.unshift Indexes::Projects
      indices.unshift Indexes::Users    # users needs to be first
      indices.push Indexes::Repos
      indices.push Indexes::Issues
      # disable for dev/test intentionally since it requires ES 8.17, uncomment if need to test in localhost
      # indices.push Indexes::IssuesSemantic
      indices.push Indexes::WorkflowRuns
      indices.push Indexes::PullRequests
      indices.push Indexes::CodeSearch
      indices.push Indexes::Commits

      indices.each { |clazz| yield clazz }

      self
    end

    # Internal: Previous versions of cisetup created an index called blank that
    # was read only, so it could not be deleted. This checks for its existence
    # and makes it deleteable if it is found.
    #
    # Once this code has been running for a while, this method can be deleted.
    def make_blank_index_deleteable
      blank = Elastomer.client.index("blank")

      if blank.exists?
        blank.update_settings(
          settings: {
            index: {
              "blocks.read_only": false,
            },
          },
        )
      end
    end

    sig { params(client: ::ElastomerClient::Client).returns(T::Array[String]) }
    def self.list_indices(client)
      index_names = client.cluster.indices.keys
      index_names
    end

    sig { params(pattern: String, client: ::ElastomerClient::Client).returns(T::Array[String]) }
    def self.fetch_followee_indices(pattern, client)
      response = client.ccr.get_follower_info(pattern)
      response["follower_indices"].map { |follower| follower["leader_index"] }.uniq
    end

    sig { params(primary_client: ::ElastomerClient::Client, replica_client: ::ElastomerClient::Client).void }
    def self.manage_follower_indices(primary_client, replica_client)
      follower_pattern = "follower_pattern"
      remote_cluster_name = "primary"

      # Get all indices on the main cluster
      main_indices = primary_client.cluster.indices.select do |index, properties|
        properties["system"] == false && !index.start_with?(".ds-", ".logs-deprecation.elasticsearch")
      end.keys

      # Fetch all followee indices
      followee_indices = fetch_followee_indices("*", replica_client)

      main_indices.each do |index|
        unless followee_indices.include?(index)
          replica_index = replica_client.index(index)

          # If the follower index exists but isn't following the leader, we should delete it
          if replica_index.exists?
            replica_index.delete
          end

          replica_client.ccr.follow(index, { leader_index: index, remote_cluster: remote_cluster_name })
        end
      end

      begin
        replica_client.ccr.get_auto_follow(pattern_name: follower_pattern)["patterns"].each do |pattern|
          replica_client.ccr.delete_auto_follow(pattern["name"])
        end
      rescue ElastomerClient::Client::RequestError => e
        if e.message.include?("resource_not_found_exception")
          STDERR.puts "Auto-follow pattern already does not exist."
        else
          raise e
        end
      end

      replica_client.ccr.auto_follow(
        follower_pattern,
        {
          remote_cluster: remote_cluster_name,
          leader_index_patterns: ["*"],
          follow_index_pattern: "{{leader_index}}",
        }
      )
    end

    # Promote CCR indexes from follower to primary indexes
    #
    # client - An instance of ElastomerClient::Client for the follower cluster.
    #
    # This method performs the following operations for each index in the follower cluster:
    # 1. Pause following the leader index.
    # 2. Close the index.
    # 3. Unfollow the leader index.
    # 4. Reopen the index.
    #
    # Returns nothing.
    def self.promote_follower_indexes_to_primary(client)
      # Fetch all follower indices
      follower_indices = client.ccr.get_follower_info("*")["follower_indices"]

      follower_indices.each do |follower|
        index_name = follower["follower_index"]
        index = client.index(index_name)
        begin
          # Pause following
          client.ccr.pause_follow(index_name)
          puts "Paused following for index: #{index_name}"

          # Close the index
          index.close
          puts "Closed index: #{index_name}"

          # Unfollow the leader index
          client.ccr.unfollow(index_name)
          puts "Unfollowed leader for index: #{index_name}"

          # Reopen the index
          response = index.open
          puts "Reopened index: #{index_name}"
        rescue ElastomerClient::Client::RequestError => e
          STDERR.puts "Error promoting index #{index_name}: #{e.message}"
        end
      end
    end

    # ES8-COMPATIBILITY - ES8 requires a name to be provided when deleting an index.
    # Set setting to allow deleting indices without a name.
    def enable_wildcard_deletion
      if client.version_support.es_version_8_plus?
        client.cluster.update_settings(
          persistent: {
            "action.destructive_requires_name": false
          },
        )
      end
    end
  end
end
