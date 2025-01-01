# typed: true
# frozen_string_literal: true

class CodeQLActionCreator
  def self.create_codeql_action
    codeql_action_repo_name = "#{github_org_name}/codeql-action"
    GitHub.logger.info(
      "Using enterprise actions admin to populate codeql-action repo...",
      "gh.actor.login" => owner_login,
      "gh.repo.name_with_owner" => codeql_action_repo_name
    )

    owner = find_owner(owner_login)
    github_org = find_org(owner, github_org_name)

    run_installer(owner, codeql_action_repo_name)
    GitHub.logger.info("All done!")
  end

  def self.owner_login
    ENV.fetch("ENTERPRISE_ACTIONS_ADMIN_LOGIN")
  end

  def self.github_org_name
    ENV.fetch("ENTERPRISE_ACTIONS_GITHUB_ORG")
  end

  def self.run_installer(owner, codeql_action_repo_name)
    GitHub.logger.info("Creating PAT...")
    access = get_token_access(owner)
    token = access.set_random_token_pair
    access.save!

    GitHub.logger.info("Running CodeQL Action installer...")
    invoke_installer(owner, codeql_action_repo_name, token)
    GitHub.logger.info("Finished running CodeQL Action installer.")
  ensure
    GitHub.logger.info("Destroying PAT...")
    access&.destroy
    GitHub.logger.info("PAT destroyed.")
  end

  def self.codeql_action_installer_directory
    "/data/codeql-action-installer/"
  end

  def self.invoke_installer(owner, codeql_action_repo_name, token)
    attempt = 1
    loop do
      GitHub.logger.info(
        "Starting installation atempt...",
        "gh.code_scanning.codeql_action_creator.attempt" => attempt
      )
      Dir.chdir(codeql_action_installer_directory) do
        return if system(
          { "CODEQL_ACTION_SYNC_TOOL_DESTINATION_TOKEN" => token },
          "/data/codeql-action-installer/data/codeql-action-sync",
          "push",
          "--destination-url", "http://nginx-unicorn:1337/",
          "--destination-repository", codeql_action_repo_name,
          "--actions-admin-user", owner.login,
          "--force",
          "--git-url", "http://babeld:3033/#{codeql_action_repo_name}.git",
        )
      end
      if attempt < 10
        delay = [2**attempt, 30].min
        GitHub.logger.info(
          "Installer exited with non-zero exit code. Backing off and retrying after a delay...",
          "process.exit_code" => $?,
        )
        sleep delay
        attempt += 1
      else
        raise "Failed when installing CodeQL Action. Installer exited with #{$?}."
      end
    end
  end

  def self.find_owner(login)
    owner = User.find_by_login login
    return owner if owner.present?
    raise ArgumentError, "Could not find the Actions owner #{login}."
  end

  def self.find_org(owner, name)
    org = owner.organizations.find_by_login(name)
    return org if org.present?
    raise ArgumentError, "Could not find the #{name} organization owned by #{owner.login}."
  end

  def self.get_token_access(user)
    application_id = OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    application_type = OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
    description = "CodeQL Action Repository Seeding"

    existing_access = user.oauth_accesses.find_by(description: description, application_id: application_id, application_type: application_type)
    existing_access.destroy if existing_access

    access = user.oauth_accesses.build do |access|
      access.application_id = application_id
      access.application_type = application_type
      access.description = description
      access.scopes = %w[repo workflow]
      access.expires_at_timestamp = 1.hour.from_now
    end
    access
  end
end
