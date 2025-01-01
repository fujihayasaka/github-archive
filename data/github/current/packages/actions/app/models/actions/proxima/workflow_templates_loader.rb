# typed: true
# frozen_string_literal: true

class Actions::Proxima::WorkflowTemplatesLoader
  include GitHub::Memoizer
  extend T::Sig

  BASE_URL = "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}"
  CACHE_VERSION = "v1" # Change this whenever we change the cache format and need to invalidate immediately
  STATS_KEY_PREFIX = "actions.proxima.workflow.templates"
  CACHE_STATS_KEY = "#{STATS_KEY_PREFIX}.cache"

  def initialize(repo_nwo, folders, source = "default", branch = "main", **kwargs)
    @repo_nwo = repo_nwo
    @repo_owner, @repo_name = @repo_nwo.split("/")
    @folders = folders
    @source = source
    @branch = branch

    # We're going to re-use the same connection to cut down on overhead
    connection = kwargs.fetch(:connection) do
      GitHub::FaradayClient::External.new({ url: BASE_URL }) do |f|
        f.adapter Faraday.default_adapter
      end
    end

    token_generator = kwargs.fetch(:token_generator) do
      Actions::Proxima::TokenGenerator.new(connection:)
    end

    @workflow_templates_client = kwargs.fetch(:workflow_templates_client) do
      Actions::Proxima::WorkflowTemplatesClient.new(repo_owner:, repo_name:, connection:, token_generator:)
    end

    @branch_client = kwargs.fetch(:branch_client) do
      Actions::Proxima::BranchClient.new(connection:, token_generator:)
    end
  end

  sig { returns(String) }
  attr_reader :repo_nwo, :repo_owner, :repo_name, :branch

  sig { returns(T::Array[String]) }
  attr_reader :folders

  sig { returns(Actions::Proxima::WorkflowTemplatesClient) }
  attr_reader :workflow_templates_client

  sig { returns(Actions::Proxima::BranchClient) }
  attr_reader :branch_client

  memoize def all
    GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.all")
    GitHub.logger.with_named_tags(
      "code.namespace" => "Actions::Proxima::WorkflowTemplatesLoader",
      "code.function" => "all",
      "gh.repo.name_with_owner" => repo_nwo,
      "gh.branch.name" => branch,
    ) do
      workflow_folders = workflow_template_folders(folders)

      latest_sha_key = "actions:workflow_templates:latest_sha:#{CACHE_VERSION}:#{repo_nwo}:#{branch}"
      sha = kv(repo_nwo).get(latest_sha_key).value { "" }.to_s

      if sha.blank?
        sha = branch_client.sha_for_branch(repo_nwo, branch)
        GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.sha_retrieved_from_dotcom")
        GitHub.logger.info("Retrieved SHA from DotCom", { "gh.commit.sha" => sha })

        if sha.blank?
          GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.sha_retrieved_from_dotcom.blank_sha")
          GitHub.logger.info("Retrieved SHA from DotCom was blank", { "gh.commit.sha" => sha })
          return []
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          kv(repo_nwo).set(latest_sha_key, sha, expires: 1.hour.from_now.utc)
        end
      else
        GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.sha_retrieved_from_kv")
        GitHub.logger.info("Retrieved SHA from Actions KV", { "gh.commit.sha" => sha })
      end

      cached_fetch_templates(sha, workflow_folders)
    rescue Actions::Proxima::WorkflowTemplatesError => e
      GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.all.error")
      GitHub.logger.error({
        exception: e,
        url: e.url,
        status: e.status,
        body: e.body,
        errors: e.errors,
      })

      []
    end
  end

  private

  def cached_fetch_templates(sha, workflow_folders)
    folders_hash = Digest::SHA256.hexdigest(workflow_folders.join("-")) # Hash folders since they are stored in cache.
    cache_key = "actions:workflow_templates:#{CACHE_VERSION}:#{sha}:#{folders_hash}"

    value = GitHub.cache.fetch(cache_key, stats_key: CACHE_STATS_KEY) do
      raw_templates = workflow_templates_client.fetch_templates(sha, workflow_folders)
      return [] if raw_templates.blank?

      transform_raw_templates(raw_templates, sha)
    end

    GitHub.dogstats.gauge("#{CACHE_STATS_KEY}.cache_size", ObjectSpace.memsize_of(value))

    value
  end

  def workflow_template_folders(folders)
    folders.each_with_object([]) do |folder, acc|
      acc << folder

      if folder != "icons"
        properties_folder = "#{folder}/properties"
        acc << properties_folder
      end
    end
  end

  def transform_raw_templates(raw_templates, sha)
    # initialize nested hash with default values
    sections = Hash.new do |hash, key|
      hash[key] = Hash.new { |hash, key| hash[key] = {} }
    end
    icons = {}

    raw_templates.each do |_, folder_data|
      next if folder_data.nil? #folder wasn't found. Ex: There's no properties folder under icons.
      entries = folder_data["files"]

      entries.each do |entry|
        next if entry["object"].blank? # Entry is most likely a folder
        next if entry["object"]["isTruncated"] # Entry was truncated and is unusable

        filename = entry["path"]
        entry_data = entry["object"]["text"]

        if match = filename.match(/\A(.*)\.properties\.json\z/)
          section = [match[1].split("/").first, match[1].split("/").last].join("/")
          begin
            decoded = GitHub::JSON.decode(entry_data)
          rescue Yajl::ParseError
            next # Just skip this if it fails to parse cleanly
          end
          sections[section][:json] = decoded
        elsif match = filename.match(/\A(.*)\.ya?ml\z/)
          section = match[1]
          sections[section][:yaml] = entry_data
          sections[section][:path] = filename
        elsif match = filename.match(/\A(.*)\.svg\z/)
          key = match[1].split("/").last
          icons[key] = "data:image/svg+xml;base64,#{Base64.encode64(entry_data).gsub("\n", "")}"
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
          protocol:   GitHub.dotcom_host_protocol,
          host:       GitHub.dotcom_host_name,
          user_id:    repo_owner,
          repository: repo_name,
          name:       sha,
          path:       value[:path],
        ),
        "sourceRepository": repo_nwo,
        "source": @source
      }.stringify_keys
    end.compact
  end

  sig { params(repo_nwo: String).returns(GitHub::KV) }
  def kv(repo_nwo)
    Actions::KV.for_key(repo_nwo)
  end
end
