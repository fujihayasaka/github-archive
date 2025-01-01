# typed: true
# frozen_string_literal: true

module Actions
  class WorkflowTemplatesLoader
    include FeatureFlagHelper

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
      cache_key = "actions:workflow_templates:#{version}:#{sha}:#{folders_hash}"

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
          "source": @source
        }.stringify_keys
      end.compact
    end
  end
end
