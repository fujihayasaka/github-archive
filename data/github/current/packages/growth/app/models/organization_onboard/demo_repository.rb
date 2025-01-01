# typed: strict
# frozen_string_literal: true

module OrganizationOnboard
  class DemoRepository < ApplicationRecord::Domain::Repositories
    class FailedRepositoryCreationError < StandardError; end
    extend T::Sig

    DEFAULT_NAME = "demo-repository"
    ACTIONS_WORKFLOW_BRANCH_NAME = "add-badges-to-readme"

    belongs_to :repository
    destroy_in_background_with :repository
    belongs_to :organization

    sig { params(organization: Organization).returns(T.nilable(Repository)) }
    def self.repository_for(organization)
      repo = joins(:repository).find_by(organization: organization)&.repository
      return repo if repo

      # This is the old behavior we used to create the demo repository. This will be removed once we migrate
      # old demo repos to the new behavior (having a DemoRepository record).
      repo = organization.repositories.find_by(name: DEFAULT_NAME)
      return repo if repo&.created_for_demo_by_gh?
    end

    sig { params(organization: Organization, actor: User).returns(SecurityProduct::Result) }
    def self.enable_ghas_and_secret_scanning(organization, actor)
      # We need this to ensure we get both behaves: Old and New.
      # When we remove the old behavior, we can move this to an instance method.
      repo = repository_for(organization)
      return SecurityProduct::Result.new(false, "Missing demo repository.") unless repo

      response = repo.enable_advanced_security(actor: actor)
      return response unless response && !response.error?
      response = SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [:token_scanning])
    end

    sig { params(actor: User).returns(T.nilable(Repository)) }
    def setup(actor)
      org = T.must_because(organization) { "DemoRepository must belong to an organization" }
      return if self.class.repository_for(org)

      GitHub.logger.info("setting up demo repository",
        "gh.actor.login": actor.login,
        "gh.org.login": org.login,
        "code.namespace": "OrganizationOnboard::DemoRepository",
        "code.function": "setup"
      )

      result = Repository.handle_creation(
        actor,
        org,
        {
          name: generate_repo_name,
          owner: org,
          has_wiki: false,
          public: false,
          created_by_user_id: actor.id,
          description: "A code repository designed to show the best GitHub has to offer."
        },
        skip_validation: true
      )
      if result.success?
        self.repository = result.repository
        repo = T.must_because(repository) { "DemoRepository must be backed by a repository" }
      else
        raise FailedRepositoryCreationError.new(result.error_message)
      end

      repo.setup_git_repository

      main_branch = setup_main_branch
      setup_workflow_branch(main_branch)
      repo.enable_actions_app(
        actor: actor,
        entry_point: :organization_onboard_demo_repository_setup
      )
      save
      repository
    end

    private

    sig { returns(String) }
    def generate_repo_name
      org = T.must_because(organization) { "DemoRepository must belong to an organization" }
      return DEFAULT_NAME unless org.repositories.exists?(name: DEFAULT_NAME)

      "#{Repository::SuggestedName.generate}-#{DEFAULT_NAME}"
    end

    sig { returns(Git::Ref) }
    def setup_main_branch
      repo = T.must_because(repository) { "DemoRepository must be backed by a repository" }

      main_branch = repo.heads.find_or_build(repo.owner_default_new_repo_branch)
      if main_branch.target_oid.nil?
        args = [nil, commit_info("Initial commit"), main_repo_files(repo.created_by)]
        commit_oid = repo.rpc.create_tree_changes(*args, &repo.method(:sign_commit))
        main_branch.update(commit_oid, repo.created_by)
      end
      main_branch
    end

    sig { params(main_branch: Git::Ref).void }
    def setup_workflow_branch(main_branch)
      repo = T.must_because(repository) { "DemoRepository must be backed by a repository" }

      workflow_branch = repo.heads.find(ACTIONS_WORKFLOW_BRANCH_NAME)
      workflow_branch ||= repo.heads.create(ACTIONS_WORKFLOW_BRANCH_NAME, main_branch.target, repo.owner)
      workflow_branch.append_commit({ message: "Add workflow badges to README", committer: repo.created_by }, repo.created_by) do |files|
        workflow_repo_files(repo).each { |key, value| files.add(key, value) }
      end
    end

    sig { params(repository: Repository).returns(T::Hash[String, T.untyped]) }
    def workflow_repo_files(repository)
      {
        "README.md" => {
          "data" => new_readme_content(repository)
        }
      }
    end

    sig { params(message: String).returns(T::Hash[String, T.untyped]) }
    def commit_info(message)
      repo = T.must_because(repository) { "DemoRepository must be backed by a repository" }

      author = {
        "name" => repo.created_by.git_author_name,
        "email" => repo.created_by.git_author_email,
        "time" => Time.zone.now.iso8601,
      }

      committer = {
        "email" => GitHub.web_committer_email,
        "name"  => GitHub.web_committer_name,
        "time"  => author["time"],
      }

      {
        "message" => message,
        "committer" => committer,
        "author" => author,
      }
    end

    sig { params(assigned_user: User).returns(T::Hash[String, T.untyped]) }
    def main_repo_files(assigned_user)
      files = {}
      files["README.md"] = { "data" => readme_content }
      files["index.html"] = { "data" => index_content }
      files[".github/workflows/auto-assign.yml"] = { "data" => auto_assign_base_content(assigned_user) }
      files[".github/workflows/proof-html.yml"] = { "data" => proof_html_content }
      files["package.json"] = { "data" => package_content }
      files
    end

    sig { returns(String) }
    def readme_content
      <<~MARKDOWN
      # Welcome to your organization's demo respository
      This code repository (or "repo") is designed to demonstrate the best GitHub has to offer with the least amount of noise.

      The repo includes an `index.html` file (so it can render a web page), two GitHub Actions workflows, and a CSS stylesheet dependency.
      MARKDOWN
    end

    sig { returns(String) }
    def index_content
      <<~HTML
      <h1>Welcome to the website generated by my demo repository</h1>
      HTML
    end

    sig { params(repository: Repository).returns(String) }
    def new_readme_content(repository)
      org = T.must_because(organization) { "DemoRepository must belong to an organization" }
      <<~MARKDOWN
      ![Auto Assign](https://github.com/#{org.name_with_display_owner}/#{repository.name}/actions/workflows/auto-assign.yml/badge.svg)

      ![Proof HTML](https://github.com/#{org.name_with_display_owner}/#{repository.name}/actions/workflows/proof-html.yml/badge.svg)

      # Welcome to your organization's demo respository
      This code repository (or "repo") is designed to demonstrate the best GitHub has to offer with the least amount of noise.

      The repo includes an `index.html` file (so it can render a web page), two GitHub Actions workflows, and a CSS stylesheet dependency.
      MARKDOWN
    end

    sig { params(assigned_user: User).returns(String) }
    def auto_assign_base_content(assigned_user)
      <<~YAML
      name: Auto Assign
      on:
        issues:
          types: [opened]
        pull_request:
          types: [opened]
      jobs:
        run:
          runs-on: ubuntu-latest
          permissions:
            issues: write
            pull-requests: write
          steps:
          - name: 'Auto-assign issue'
            uses: pozil/auto-assign-issue@v1
            with:
                repo-token: ${{ secrets.GITHUB_TOKEN }}
                assignees: #{assigned_user.login}
                numOfAssignee: 1
      YAML
    end

    sig { returns(String) }
    def proof_html_content
      <<~YAML
      name: Proof HTML
      on:
        push:
        workflow_dispatch:
      jobs:
        build:
          runs-on: ubuntu-latest
          steps:
            - uses: anishathalye/proof-html@v1.1.0
              with:
                directory: ./
      YAML
    end

    sig { returns(String) }
    def package_content
      <<~YAML
      {
        "name": "demo-repo",
        "version": "0.2.0",
        "description": "A sample package.json",
        "dependencies": {
          "@primer/css": "17.0.1"
        },
        "license": "MIT"
      }
      YAML
    end
  end
end
