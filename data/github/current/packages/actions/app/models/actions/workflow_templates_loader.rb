# typed: true
# frozen_string_literal: true

module Actions
  class WorkflowTemplatesLoader

    def initialize(nwo, folders, source = "default", user = nil)
      @nwo = nwo
      @folders = folders
      @source = source
      @current_user = user
    end

    def all
      return @templates if defined?(@templates)
      @templates = cached_load_from_repo
    end

    private

    def cached_load_from_repo
      return [] unless repo = Repository.nwo(@nwo)

      sha = repo.root_directory&.commit_sha
      return [] unless sha

      version = "v4" # In case we change the data format and need to bust the cache
      folders_hash = Digest::SHA256.hexdigest(@folders.join("-")) # Hash folders since they are stored in cache.
      # Include feature flag state in cache key to separate cached data with/without visibility
      visibility_tracking = FeatureFlag.vexi.enabled?(:workflow_template_visibility_tracking, @current_user, repo&.owner, default: false)

      # For owner templates with visibility tracking, include .github repo visibility in cache key to ensure fresh data
      github_visibility = ""
      if visibility_tracking && @source == "owner"
        begin
          github_repo = repo.owner.repositories.find_by_name(".github")
          github_visibility = ":github_#{github_repo&.visibility || 'unknown'}"
        rescue => e
          # Fallback to "owner" if .github repo is unavailable (e.g., during repository moves)
          github_visibility = ":github_owner"
          Rails.logger.warn("WorkflowTemplatesLoader cache key - Failed to fetch .github repo visibility for #{repo.nwo}, using fallback: #{e.message}")
        end
      end

      cache_key = "actions:workflow_templates:#{version}:#{sha}:#{folders_hash}:visibility_#{visibility_tracking}#{github_visibility}"

      value = GitHub.cache.fetch(cache_key, stats_key: "actions.workflow.templates.cache") do
        load_from_repo(repo, sha, @folders)
      end
    end

    def load_from_repo(repo, sha, folders)
      sections = {}
      icons = {}

      folders.each do |folder|
        begin
          _, entries, _ = repo.tree_entries(sha, folder, recursive: true)
        rescue GitRPC::NoSuchPath, GitRPC::InvalidObject
          next
        end

        entries.each do |entry|
          next if entry.directory?

          filename = entry.path

          if match = filename.match(/\A(.*)\.properties\.json\z/)
            section = [match[1].split("/").first, match[1].split("/").last].join("/")
            sections[section] ||= {}
            begin
              decoded = GitHub::JSON.decode(entry.data)
            rescue Yajl::ParseError
              next # Just skip this if it fails to parse cleanly
            end
            sections[section][:json] = decoded
          elsif match = filename.match(/\A(.*)\.ya?ml\z/)
            section = match[1]
            sections[section] ||= {}
            sections[section][:yaml] = entry.data
            sections[section][:path] = entry.path
          elsif match = filename.match(/\A(.*)\.svg\z/)
            key = match[1].split("/").last
            if entry&.language&.name == "SVG"
              icons[key] = "data:image/svg+xml;base64,#{Base64.encode64(entry.data).gsub("\n", "")}"
            end
          end
        end
      end

      # Feature flag determines whether to include visibility tracking (minimal blast radius)
      if FeatureFlag.vexi.enabled?(:workflow_template_visibility_tracking, @current_user, repo&.owner, default: false)
        # Feature flag ON: Include visibility tracking
        sections.map do |key, value|
          next unless value.keys.sort == [:json, :path, :yaml] && value[:json]
          # If you change the data returned here, make sure you update the cache key version above
          icon = value[:json]["iconName"]

          # Determine visibility based on template source
          if repo.nwo == GitHub.actions_starter_workflows_nwo
            visibility = "shared"
          elsif @source == "owner"
            # For owner templates, get the actual .github repository visibility (NOT CACHED - fresh data)
            github_repo = repo.owner.repositories.find_by_name(".github")
            visibility = github_repo&.visibility || "unknown"
          else
            visibility = repo.visibility
          end
          {
            "id": key,
            "data": Base64.strict_encode64(value[:yaml]),
            "name": value[:json]["name"],
            "categories": value[:json]["categories"],
            "labels": value[:json].fetch("labels", []),
            "creator": value[:json]["creator"],
            "description": value[:json]["description"],
            "filePatterns": value[:json]["filePatterns"],
            "iconName": icon,
            "iconRawUrl": icons[icon],
            "templateUrl": UrlHelpers.blob_url(
              protocol:   GitHub.scheme,
              host:       GitHub.host_name,
              user_id:    repo.owner,
              repository: repo,
              name:       sha,
              path:       value[:path],
            ),
            "sourceRepository": repo.nwo,
            "source": @source,
            "visibility": visibility
          }.stringify_keys
        end.compact
      else
        # Feature flag OFF: Original behavior (unchanged)
        sections.map do |key, value|
          next unless value.keys.sort == [:json, :path, :yaml] && value[:json]
          # If you change the data returned here, make sure you update the cache key version above
          icon = value[:json]["iconName"]
          {
            "id": key,
            "data": Base64.strict_encode64(value[:yaml]),
            "name": value[:json]["name"],
            "categories": value[:json]["categories"],
            "labels": value[:json].fetch("labels", []),
            "creator": value[:json]["creator"],
            "description": value[:json]["description"],
            "filePatterns": value[:json]["filePatterns"],
            "iconName": icon,
            "iconRawUrl": icons[icon],
            "templateUrl": UrlHelpers.blob_url(
              protocol:   GitHub.scheme,
              host:       GitHub.host_name,
              user_id:    repo.owner,
              repository: repo,
              name:       sha,
              path:       value[:path],
            ),
            "sourceRepository": repo.nwo,
            "source": @source,
          }.stringify_keys
        end.compact
      end
    end
  end
end
