# typed: true
# frozen_string_literal: true

module Actions
  class WorkflowTemplates
    PUBLIC_CONFIG_REPO_NAME = ".github"
    INTERNAL_CONFIG_REPO_NAME = ".github-internal"
    PRIVATE_CONFIG_REPO_NAME = ".github-private"
    LOCAL_CONFIG_REPO_NAME = ".github-local"
    CONFIG_REPO_FOLDERS = ["workflow-templates"]
    STARTER_WORKFLOWS_FOLDERS = %w[automation ci code-scanning deployments icons pages]
    CODEQL_RUNS_ON = "${{ (matrix.language == 'swift' && 'macos-latest') || 'ubuntu-latest' }}"

    def initialize(repo, user)
      @user = user
      @repo = repo
    end

    def get_by_id(id)
      all.find do |template|
        template["id"] == id
      end
    end

    def get_by_category(category)
      all.select do |template|
        template["categories"] && template["categories"].include?(category)
      end
    end

    def all
      return @templates if defined?(@templates)

      @templates = owner_templates + shared_templates

      # keep only first of each ID, following override precedence defined above
      # NB uniq! returns nil if no changes are made to the array
      @templates.uniq! { |t| t["id"] }

      @templates
    end

    def shared_templates
      return @shared_templates if defined?(@shared_templates)

      if GitHub.multi_tenant_enterprise? && !Rails.env.development?
        @shared_templates = Actions::Proxima::WorkflowTemplatesLoader.new(GitHub.actions_starter_workflows_nwo, STARTER_WORKFLOWS_FOLDERS, "default", "main").all
      else
        @shared_templates = Actions::WorkflowTemplatesLoader.new(GitHub.actions_starter_workflows_nwo, STARTER_WORKFLOWS_FOLDERS, "default", @user).all
      end
    end

    def owner_templates
      return @owner_templates if defined?(@owner_templates)

      # Order matters here, because `get_by_id` processes them in order. Local templates take precedence over private, then over
      # internal and then over public ones, which take precedence over the default ones.
      @owner_templates = owner_local_templates + owner_private_templates + owner_internal_templates + owner_public_templates

      # keep only first of each ID, following override precedence defined above
      # NB uniq! returns nil if no changes are made to the array
      @owner_templates.uniq! { |t| t["id"] }

      @owner_templates
    end

    def self.get_yaml_by_id(id, repo, user)
      template = Actions::WorkflowTemplates.new(repo, user).get_by_id(id)
      return "" unless template

      yml = Base64.decode64(template["data"])

      self.process_workflow_templating(yml, repo)
    end

    def self.process_workflow_templating(yml, repo)
      if use_self_hosted_labels?
        if yml.include?(CODEQL_RUNS_ON)
          # CodeQL's starter workflow has a particularly complex runs-on expression, where the standard replacement doesn't work.
          # For now we are special-casing the exact expression we expect.
          yml.gsub!(CODEQL_RUNS_ON, "${{ (matrix.language == 'swift' && fromJSON('[ \"self-hosted\", \"macOS\" ]')) || 'self-hosted' }}")
        else
          yml.gsub!(/ubuntu-latest/i, "[ self-hosted ]")
          yml.gsub!(/windows-latest/i, "[ self-hosted, windows ]")
          yml.gsub!(/macos-latest/i, "[ self-hosted, macOS ]")
        end
      end

      yml.gsub!("$default-branch", repo.default_branch.to_json) # Force a JSON string in case the branch is not Yaml safe
      yml.gsub!("$protected-branches", repo.protected_branches_for_code_scanning_workflow(exclude_default_branch: true).sort.join(", "))
      # hacky, but we might now have trailing commas to clean up
      yml.gsub!(/\,\s*\]/, " ]")

      # we generate a random cron strings, but avoiding the top of the hour
      yml.gsub!("$cron-hourly", "'#{SecureRandom.rand(15..45)} * * * *'")
      yml.gsub!("$cron-daily", "'#{SecureRandom.rand(15..45)} #{SecureRandom.rand(0..23)} * * *'")
      yml.gsub!("$cron-weekly", "'#{SecureRandom.rand(15..45)} #{SecureRandom.rand(0..23)} * * #{SecureRandom.rand(0..6)}'")

      # customise the languages matrix found in the CodeQL template
      yml.gsub!(/(?<=\n)\s*\$codeql-languages-matrix/, self.codeql_matrix(repo)) # More recent templates use the explicit matrix
      yml.gsub!("$detected-codeql-languages", repo.detected_codeql_languages_string)
      yml.gsub!("$supported-codeql-languages", repo.supported_codeql_languages_string)

      Registry::Package::PUBLICLY_SUPPORTED_TYPES.each do |type|
        type_name = type.to_s
        yml.gsub!("$registry-url(#{type_name})", GitHub.urls.registry_url(type))
      end

      yml.force_encoding("utf-8")
    end

    private

    # Load templates present in public .github repo
    def owner_public_templates
      if public_owner_level_templates_allowed? && public_config_repo
        templates = Actions::WorkflowTemplatesLoader.new(public_config_repo.nwo, CONFIG_REPO_FOLDERS, "owner").all
      end
      templates || []
    end

    # Load templates present in internal .github-internal repo
    def owner_internal_templates
      return [] unless internal_owner_level_templates_allowed? && internal_config_repo
      templates = Actions::WorkflowTemplatesLoader.new(internal_config_repo.nwo, CONFIG_REPO_FOLDERS, "owner").all
    end

    # Load templates present in private .github-private repo
    def owner_private_templates
      return [] unless private_owner_level_templates_allowed? && private_config_repo
      templates = Actions::WorkflowTemplatesLoader.new(private_config_repo.nwo, CONFIG_REPO_FOLDERS, "owner").all
    end

    # Load templates present in private or internal .github-local repo
    def owner_local_templates
      return [] unless local_owner_level_templates_allowed? && local_config_repo
      templates = Actions::WorkflowTemplatesLoader.new(local_config_repo.nwo, CONFIG_REPO_FOLDERS, "owner").all
    end

    def public_config_repo
      @repo.owner.public_repositories.find_by_name(PUBLIC_CONFIG_REPO_NAME)
    end

    def internal_config_repo
      fetched_repo = @repo.owner.repositories.find_by_name(INTERNAL_CONFIG_REPO_NAME)
      fetched_repo&.visibility == Repository::INTERNAL_VISIBILITY ? fetched_repo : nil
    end

    def private_config_repo
      fetched_repo = @repo.owner.repositories.find_by_name(PRIVATE_CONFIG_REPO_NAME)
      fetched_repo&.visibility == Repository::PRIVATE_VISIBILITY ? fetched_repo : nil
    end

    def local_config_repo
      @repo.owner.repositories.find_by_name(LOCAL_CONFIG_REPO_NAME)
    end

    def public_owner_level_templates_allowed?
      @repo.public? || @repo.owner.plan.business_plus? || @repo.owner.plan.enterprise?
    end

    def internal_owner_level_templates_allowed?
      return false unless GitHub.flipper[:internal_private_workflow_templates].enabled?(@user) || GitHub.flipper[:internal_private_workflow_templates].enabled?(@repo.owner)
      !@repo.public? && (@repo.owner.plan.business_plus? || @repo.owner.plan.enterprise?)
    end

    def private_owner_level_templates_allowed?
      return false unless GitHub.flipper[:internal_private_workflow_templates].enabled?(@user) || GitHub.flipper[:internal_private_workflow_templates].enabled?(@repo.owner)
      @repo.visibility == Repository::PRIVATE_VISIBILITY && (@repo.owner.plan.business_plus? || @repo.owner.plan.enterprise?)
    end

    def local_owner_level_templates_allowed?
      return false unless GitHub.flipper[:internal_workflow_templates].enabled?(@user) || GitHub.flipper[:internal_workflow_templates].enabled?(@repo.owner)
      !@repo.public? && (@repo.owner.plan.business_plus? || @repo.owner.plan.enterprise?)
    end

    # To ensure starter workflows work in other environments, we don't want to use hosted runner labels
    def self.use_self_hosted_labels?
      return true if GitHub.enterprise?

      # Are we in a Codespaces development environment?
      !!(Rails.env.development? && ENV["CODESPACES"])
    end
    private_class_method :use_self_hosted_labels?

    def self.codeql_matrix(repo)
      # TODO: In the future, we might include the runs-on in the matrix
      matrix = ["include:"]
      repo.detected_codeql_languages_build_mapping.each do |language, build_mode|
        matrix << "- language: #{language}"
        matrix << "  build-mode: #{build_mode}"
      end
      matrix.join("\n").indent(8)
    end
    private_class_method :codeql_matrix

  end
end
