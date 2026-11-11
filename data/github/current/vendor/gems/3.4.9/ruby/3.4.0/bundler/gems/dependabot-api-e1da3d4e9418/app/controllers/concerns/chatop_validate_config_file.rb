# frozen_string_literal: true

module ChatopValidateConfigFile
  extend ActiveSupport::Concern

  included do
    chatop :validate_config_file,
           /validate[-_\s]config[-_\s]file\s+(?<github_nwo>.*)/,
           "validate config file NWO [--tenant TENANT] " \
           "- Fetches the `.github/dependabot.yaml` configuration file for this repo and validates it" do
      github_nwo = jsonrpc_params[:github_nwo]
      tenant = jsonrpc_params[:tenant]
      repo = find_by_nwo!(github_nwo, tenant)

      latest_config_file = FetchConfigFile.new(
        account: repo.account,
        repo_name: repo.name,
        repo_github_id: repo.github_id,
      ).run

      parsed_config = ParseConfigFile.new(config_file: latest_config_file, repo: repo)
      parsed_config.run
      ValidateConfigFile.validate_registries(parsed_config.registries)

      jsonrpc_success "The config file for #{github_nwo} looks valid"
    rescue ParseConfigFile::Unparseable, ParseConfigFile::Invalid => e
      error_presenter = ValidateConfigFile.format_error(e, latest_config_file)
      message = <<~MSG
        Found the following configuration issues:

        #{error_presenter.issue_body}
        #{error_presenter.issue_title}
      MSG

      jsonrpc_success(message)
    end
  end
end
