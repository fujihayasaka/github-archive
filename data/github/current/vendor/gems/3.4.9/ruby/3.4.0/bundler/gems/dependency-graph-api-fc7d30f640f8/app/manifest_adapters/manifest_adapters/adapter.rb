module ManifestAdapters
  class Adapter
    # Public: Can this adapter handle a particular file?
    #
    # Returns Boolean
    def self.test(filename:, path:)
      !!manifest_type(filename: filename, path: path)
    end

    # Public: What type of manifest is a particular file?
    #
    # Returns a Types::Manifest or nil if the adapter doesn't recognize the file
    #   as a manifest.
    def self.manifest_type(**_args)
      raise NotImplementedError.new("Abstract method called!")
    end

    # Public: Parse manifest file into a generic manifest.
    #
    # Returns a Manifest
    def self.parse(**args)
      new(**args).parse
    end

    def initialize(filename:, path:, content:, git_ref:, pushed_at:,
                   github_repository_id:, github_owner_id: nil, repository_nwo: nil, repository_stargazer_count: 0, fork:, visibility_private:, is_backfill: false)
      #NOTE that repository_nwo defaults to nil. If we ever fully get rid of the github repository ids, this should become required.
      @filename              = filename
      @path                  = path.to_s
      @content               = content
      @git_ref               = git_ref.to_s
      @github_repository_id  = Integer(github_repository_id)
      @github_owner_id       = github_owner_id
      @repository_nwo        = repository_nwo
      @repository_stargazer_count = repository_stargazer_count
      @fork                  = !!fork
      @visibility_private    = !!visibility_private
      @pushed_at             = Time.parse(pushed_at.to_s) unless pushed_at.to_s.empty?
      @malformed_dependencies = false
      @is_backfill = is_backfill
    end

    # Public: Parse manifest file into a generic manifest.
    #
    # Returns a Manifest
    def parse
      span_class_name = self.class.to_s
      GitHub::Telemetry.tracer.in_span("#{span_class_name}#parse") do
        start_time = Time.now
        parsed_dependencies = []

        dependency_parsing_error = nil
        begin
          parsed_dependencies = parsed&.dependencies
        rescue ManifestAdapters::Npm::UnityManifestError
          DependencyGraph.logger.info("Unity manifest detected",
            "gh.repo.id" => github_repository_id,
            "gh.git.ref" => git_ref,
          )
          @manifest_type = Types::Manifest[:unknown]
        rescue => e
          dependency_parsing_error = e
          # Rescue when parsing dependencies, but set malformed to true so that the ManifestLoader will
          @malformed_dependencies = true
        end

        manifest = ManifestAdapters::Manifest.new(
            package_manager: self.class.package_manager,
            manifest_type: manifest_type,
            dependent_name: parsed&.name,
            dependent_version: parsed&.version,
            filename: filename,
            path: path,
            git_ref: git_ref,
            pushed_at: pushed_at,
            github_repository_id: github_repository_id,
            github_owner_id: github_owner_id,
            repository_nwo: repository_nwo,
            repository_stargazer_count: repository_stargazer_count,
            fork: fork?,
            visibility_private: private_repository?,
            malformed: malformed?,
            dependencies: parsed_dependencies,
            is_backfill: is_backfill,
            parser_class: parsed&.class
          )

        end_time = Time.now
        duration_ms = (end_time - start_time).in_milliseconds

        trace_manifest_parsed(manifest, dependency_parsing_error, duration_ms)

        manifest
      end
    end

    def self.package_manager
      raise NotImplementedError.new("Abstract method called!")
    end

    private

    def parsed
      raise NotImplementedError.new("Abstract method called!")
    end

    def malformed?
      parsed.nil? || parsed.blank? || parsed.try(:malformed?) || @malformed_dependencies
    end

    # Internal: File basename.
    #
    # Returns String
    attr_reader :filename

    # Internal: File path. A path of "" indicates a file at the root.
    #
    # Returns String
    attr_reader :path

    # Internal: Git revision.
    #
    # Returns String
    attr_reader :git_ref

    # Internal: Time of manifest push.
    #
    # Returns Time
    attr_reader :pushed_at

    # Internal: The github/github repository ID
    #
    # Returns Integer
    attr_reader :github_repository_id

    # Internal: The github/github owner ID
    #
    # Returns Integer
    attr_reader :github_owner_id

    # Internal: The repository name with owner
    #
    # Returns String
    attr_reader :repository_nwo

    # Internal: The repository stargazer count
    #
    # Returns Integer
    attr_reader :repository_stargazer_count

    # Internal: The raw manifest content.
    #
    # Returns String
    attr_reader :content

    # Internal: Is the manifest part of a backfill
    #
    # Returns Bool
    attr_reader :is_backfill

    # Internal: Is the manifest from a fork?
    #
    # Returns Boolean
    def fork?
      @fork
    end

    # Internal: is the manifest from a private repository?
    #
    # Returns Boolean
    def private_repository?
      @visibility_private
    end

    # Internal: What type of manifest is this?
    #
    # Returns a Types::Manifest
    def manifest_type
      return @manifest_type if defined? @manifest_type
      @manifest_type = self.class.manifest_type(filename: filename, path: path)
    end

    def trace_manifest_parsed(manifest, dependency_parsing_error, parse_time_ms)
      payload = get_reporting_payload(manifest)

      Instrument.distribution(
        "manifest_adapter.parse_time",
        parse_time_ms,
        adapter: self.class.to_s,
        is_backfill: payload["gh.dependency_graph.manifest.is_backfill"],
        malformed: payload["gh.dependency_graph.manifest.is_malformed"],
        manifest_type: payload["gh.dependency_graph.manifest.type"],
        package_manager: payload["gh.dependency_graph.package_manager"],
        parser_class: payload["gh.dependency_graph.manifest.parser_class"]
      )

      if manifest.malformed?
        Instrument.increment(
          "manifest_adapter.invalid_manifest",
          package_manager: payload["gh.dependency_graph.package_manager"],
          manifest_type: payload["gh.dependency_graph.manifest.type"],
          is_backfill: payload["gh.dependency_graph.manifest.is_backfill"],
        )
        if dependency_parsing_error != nil
          # Instead of spamming Sentry, count on other telemetry to tell us that malformed is rising and log the error to splunk.
          payload = payload.merge({ dependency_parsing_error: dependency_parsing_error.to_s })
        end

        DependencyGraph.logger.warn(payload)
      else
        Instrument.increment("manifest_adapter.valid_manifest", **payload)
        DependencyGraph.logger.info(payload.merge({ "gh.dependency_graph.manifest.parse_time" => parse_time_ms }))
      end
    end

    def get_reporting_payload(manifest)
      {
        "gh.dependency_graph.manifest.has_malformed_dependencies" => @malformed_dependencies,
        "gh.dependency_graph.package_manager" => manifest.package_manager,
        "gh.dependency_graph.manifest.type" => manifest.manifest_type,
        "gh.dependency_graph.manifest.filename" => manifest.filename,
        "gh.dependency_graph.manifest.path" => manifest.path,
        "gh.dependency_graph.manifest.filesize" => content.bytesize,
        "gh.git.ref" => manifest.git_ref,
        "gh.repo.pushed_at" => manifest.pushed_at,
        "gh.repo.id" => manifest.github_repository_id,
        "gh.repo.owner_id" => manifest.github_owner_id,
        "gh.repo.name_with_owner" => manifest.repository_nwo,
        "gh.repo.visibility" => manifest.visibility_private,
        "gh.dependency_graph.manifest.is_malformed" => manifest.malformed?,
        "gh.dependency_graph.manifest.is_backfill" => manifest.is_backfill,
        "gh.dependency_graph.manifest.parser_class" => manifest.parser_class.to_s,
      }
    end
  end
end
