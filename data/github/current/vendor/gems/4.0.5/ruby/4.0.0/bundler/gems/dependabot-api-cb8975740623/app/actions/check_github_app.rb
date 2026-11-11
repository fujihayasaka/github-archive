# frozen_string_literal: true

class CheckGitHubApp
  attr_reader :problems

  def initialize
    @problems = []
  end

  def run
    @problems << "GITHUB_INTEGRATION_ID is not set to a valid id" unless app_id.present? && app_id.positive?

    @problems << "GITHUB_INTEGRATION_NAME is not set" if app_name.blank?

    @problems << "GITHUB_INTEGRATION_PRIVATE_KEY is not set" if app_private_key.blank?

    # No point trying to connect if one or more config values are incorrect
    return false if @problems.any?

    github_app = false
    begin
      github_app = GitHubHelpers::ClientWithRetries.new(bearer_token: GitHubHelpers.integration_token).app
    rescue OpenSSL::PKey::RSAError
      @problems << "GITHUB_INTEGRATION_PRIVATE_KEY does not appear to be a valid private key."
    rescue StandardError => e
      @problems << <<~ERR
        Unable to connect to the '#{app_name}' app on #{target_hostname}
          #{e.class.name}: #{e}
      ERR
    end

    github_app
  end

  private

  def app_id
    Prius.get(:github_integration_id)
  end

  def app_name
    Prius.get(:github_integration_name)
  end

  def app_private_key
    Prius.get(:github_integration_private_key)
  end

  def target_hostname
    Prius.get(:target_github_url)
  end
end
