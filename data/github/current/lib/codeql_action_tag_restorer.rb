# typed: true
# frozen_string_literal: true

class CodeQLActionTagRestorer
  def self.find_repository
    codeql_action_repo_name = "#{github_org_name}/codeql-action"
    repository = Repository.nwo(codeql_action_repo_name)
  end

  def self.github_org_name
    ENV.fetch("ENTERPRISE_ACTIONS_GITHUB_ORG")
  end

  def self.restore_tags
    GitHub::Logger.info "Restoring tags to CodeQL Action repository..."
    repository = find_repository
    if repository.nil?
      GitHub::Logger.info "Exiting as there is no CodeQL Action repository."
      return
    end
    GitHub::Logger.info "Restoring release tags to #{repository.nwo}..."
    repository.releases.each do |release|
      GitHub::Logger.info "Restoring tag #{release.tag_name}..."
      if repository.refs.find(release.target_commitish).nil?
        GitHub::Logger.info "Target commitish #{release.target_commitish} does not exist, so tagging the default branch instead..."
        release.update(target_commitish: repository.default_branch)
      end
      release.create_tag_on_publish
    end
  end
end
