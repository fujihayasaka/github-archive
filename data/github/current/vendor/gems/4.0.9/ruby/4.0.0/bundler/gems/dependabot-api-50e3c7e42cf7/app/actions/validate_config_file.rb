# frozen_string_literal: true

# Validates a config file when changes are pushed to a repo and creates a Check
# Run for the given sha with any violations.
class ValidateConfigFile
  def self.validate_registries(registries)
    return if registries.nil?

    registries.each_value do |config|
      reg = Registry.new(
        { registry_type: config["type"], credentials: config.except("type").to_json },
      )
      reg.credentials_are_allowed_for_registry_type
      raise(ParseConfigFile::Invalid, reg.errors.full_messages.map { |msg| { message: msg } }) unless reg.errors.empty?
    end
  end

  def self.format_error(error, config_file)
    error_hash =
      case error
      when ParseConfigFile::Unparseable
        {
          "error-type" => "unparseable_config_file",
          "error-detail" => { "message" => error.message },
        }
      when ParseConfigFile::Invalid
        {
          "error-type" => "invalid_config_file",
          "error-detail" => { "message" => error.message },
        }
      end
    ConfigFileErrorPresenter.new(
      error_hash: error_hash,
      config_file_path: config_file.path
    )
  end

  def initialize(repo:, sha:)
    @repo = repo
    @sha = sha
  end

  def run
    return unless repo.account.active?
    return if config_file.nil?

    @run_id = create_check_run.id

    parsed_config = parse_config_file
    parsed_config.run

    self.class.validate_registries(parsed_config.registries)

    mark_commit_as_succeeded
  rescue ParseConfigFile::Unparseable, ParseConfigFile::Invalid => e
    mark_commit_as_failed(e)
  end

  private

  attr_reader :repo, :sha, :run_id

  def create_check_run
    installation_github_client.create_check_run(
      repo.github_id, config_file.path, sha
    )
  end

  def config_file
    @config_file ||=
      FetchConfigFile.new(
        account: repo.account,
        repo_name: repo.name,
        repo_github_id: repo.github_id,
        ref: sha,
      ).run
  end

  def parse_config_file
    ParseConfigFile.new(
      config_file: config_file,
      repo: repo,
    )
  end

  def mark_commit_as_succeeded
    installation_github_client.update_check_run(
      repo.github_id,
      run_id,
      conclusion: "success",
      output: {
        title: "Dependabot config file validation",
        summary: "All changes look good",
      },
    )
  end

  def mark_commit_as_failed(error)
    error_presenter = self.class.format_error(error, config_file)

    installation_github_client.update_check_run(
      repo.github_id,
      run_id,
      conclusion: "failure",
      output: {
        summary: error_presenter.issue_body,
        title: error_presenter.issue_title,
        text: "For more info on the config file format, see [the config file "\
        "documentation](https://docs.github.com/en/github/administering-a-repository/"\
        "configuration-options-for-dependency-updates#configuration-options-for-dependabotyml)",
      },
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(account: repo.account)
  end
end
