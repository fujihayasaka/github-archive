# frozen_string_literal: true

require "github_helpers"
require "dependabot/source"

# Fetches the contents of a config file. Can handle the config file, which
# should be located at `.github/dependabot.yml` (and may be in a submodule)
class FetchConfigFile
  CONFIG_FILE_PATHS = %w(.github/dependabot.yml .github/dependabot.yaml).freeze
  PRIVATE_FORK_NAME_REGEX = /-ghsa(?:-[23456789cfghjmpqrvwx]{4}){3}\z/

  def initialize(account:, repo_name:, repo_github_id:, ref: nil)
    @account = account
    @repo_name = repo_name
    @repo_github_id = repo_github_id
    @ref = ref
  end

  def run
    return unless account.active?
    return if repo_name.match?(PRIVATE_FORK_NAME_REGEX)
    return unless config_file_body

    OpenStruct.new(
      path: config_file_path,
      content: config_file_body,
    )
  end

  private

  attr_reader :account, :repo_name, :repo_github_id, :ref

  def config_file_path
    config_file_body

    @config_file_path
  end

  def config_file_body
    return @config_file_body if defined?(@config_file_body)

    @config_file_body =
      begin
        response = fetch_config_file_from_github

        Base64.decode64(response.content).force_encoding("UTF-8").encode if response&.content
      end
  end

  def fetch_config_file_from_github
    CONFIG_FILE_PATHS.each do |path|
      content = fetch_if_present(
        repo: repo_github_id,
        path: path,
        ref: ref,
      )
      content ||= fetch_config_file_from_github_submodule(path)
      next unless content

      @config_file_path = path
      return content
    end

    nil
  end

  def fetch_config_file_from_github_submodule(path)
    submodule_path = path.split("/")[0..-2].join("/").presence

    @dir_resp ||= {}

    resp =
      if @dir_resp.key?(submodule_path)
        @dir_resp[submodule_path]
      else
        fetch_if_present(
          repo: repo_github_id,
          path: submodule_path,
          ref: ref,
        )
      end

    @dir_resp[submodule_path] = resp

    return unless resp.respond_to?(:type) && resp.type == "submodule"

    # Fetch the config file using the repository name-with-owner from the
    # submodule path response
    fetch_if_present(
      repo: Dependabot::Source.from_url(resp.submodule_git_url).repo,
      path: path.split("/").last,
      ref: resp.sha,
    )
  end

  def fetch_if_present(repo:, path:, ref: nil)
    options = { path: path, ref: ref }.compact
    installation_github_client.contents(repo, options)
  rescue Octokit::NotFound
    nil
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: account)
  end
end
