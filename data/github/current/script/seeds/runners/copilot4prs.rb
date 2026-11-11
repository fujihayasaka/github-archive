# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class Copilot4prs < Seeds::Runner
      include GitHub::Memoizer

      sig { returns String }
      def self.help
        <<~HELP
        Enable Copilot features, seed sample code changes, and set up organizations for @monalisa
        HELP
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"
        require Rails.root.join("test/test_helpers/example_repositories")

        new.run(options)
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def run(options)
        create_orgs
        create_repositories
        enable_our_feature_flags
        create_pull_requests
        create_indexed_repositories
        enable_modelpicker
      rescue Faraday::ConnectionFailed
        warn "Your github/github server is not running. Please start it with ./script/server and try again."
        exit 1
      end

      private

      sig { void }
      def create_orgs
        puts "➡️ Enabling Copilot for @#{monalisa}..."
        copilot_business_org
        copilot_enterprise_org
        puts "➡️ Done enabling Copilot for @#{monalisa}!"
      end

      sig { void }
      def create_repositories
        puts "➡️ Creating repositories..."
        copilot_enterprise_repo
        copilot_prereviews_repo
        puts "➡️ Done creating repositories!"
      end

      sig { void }
      def enable_our_feature_flags
        puts "➡️ Enabling feature flags..."
        [
          "copilot_dotcom_chat",
          "copilot_conversational_ux_license_check",
          "copilot-api-staff-only-logging",
          "copilot_chat_sso",
          "copilot_api_enable_model_gpt4_switzerlandnorth",
          "copilot_api_enable_model_gpt35turbo_switzerlandnorth",
          "copilot-api-implicit-url",
          "copilot_reviews",
          "copilot_api_model_rollout_o4_mini_integrations_no_users",
          "copilot_api_enable_model_bento_anthropic", # Enables the dev endpoint for haiku 4.5
        ].each do |feature_flag|
          puts "Enabling #{feature_flag} feature..."
          Seeds::Objects::FeatureFlag.enable(feature_flag: feature_flag)
        end
        puts "➡️ Done enabling feature flags!"
      end

      # Keys are branches that exist in the test/fixtures/git/examples/copilot_prereviews.git repository.
      # To add new examples, you can clone the test repo, add files to the `main` branch, create a new branch
      # and change the files, push your changes to origin for both branches, and add your new branch to this hash.
      #
      # In a Codespace:
      #
      #     cd /workspaces
      #     git clone /workspaces/github/test/fixtures/git/examples/copilot_prereviews.git
      #     cd copilot_prereviews
      #     # Make your changes to main, add new branches and files, etc.
      #     git push origin
      COPILOT_PREREVIEWS_EXAMPLE_PULL_REQUESTS = {
        "example1" => {
          title: "Update #react_props in controller",
          body: "Please consider my changes to this Rails controller.",
        },
        "example2" => {
          title: "Update Avatar.tsx",
          body: "I have improved the Avatar React component.",
        },
        "example3" => {
          title: 'Introduce parseReturns option to avoid parsing "Returns" statements',
          body: "Example from https://github.com/atom/atomdoc/pull/21/commits/" \
            "10df494f47c91bb85893815be3d109913382fd1f.",
        },
        "example4" => {
          title: "Making a change to an excluded file",
          body: "We are making a change to the file_to.exclude file which should be filtered out by our diff filter resulting in an empty diffHunk object"
        },
        "example5" => {
          title: "Making a change to both excluded and non-excluded files",
          body: "We are making a change to the file_to.exclude and the sample controller which should result in a diffHunk object containing only the sample controller"
        },
      }.freeze

      sig { void }
      def create_pull_requests
        puts "➡️ Creating pull requests..."

        COPILOT_PREREVIEWS_EXAMPLE_PULL_REQUESTS.each do |head_branch, pr_details|
          create_pull_request(copilot_prereviews_repo, head_branch, pr_details)
          create_pull_request(copilot_enterprise_repo, head_branch, pr_details)
        end

        puts "➡️ Done creating pull requests!"
      end

      sig do
        params(repo: Repository, head_branch: String, pr_details: T::Hash[Symbol, T.untyped]).returns(PullRequest)
      end
      def create_pull_request(repo, head_branch, pr_details)
        ensure_no_open_pull_request_exists(repo, head_branch)

        base_branch = repo.default_branch

        puts "Creating #{repo.nwo} pull request for #{head_branch}..."
        ::PullRequest.create_for!(repo,
          user: monalisa,
          title: pr_details[:title] || head_branch,
          body: pr_details[:body] || "I made some changes to see how Copilot would review them.",
          head: head_branch,
          base: base_branch,
          draft: true,
        )
      end

      sig { params(repo: Repository, head_branch: String).void }
      def ensure_no_open_pull_request_exists(repo, head_branch)
        existing_pull = PullRequest.find_open_based_on_ref(repo, head_branch).first
        if existing_pull
          puts "Pull request already exists for #{head_branch}, closing it..."
          existing_pull.close(monalisa)
        end
      end

      memoize def copilot_prereviews_repo
        nwo = "#{monalisa}/smile"
        puts "Ensuring #{nwo} exists..."
        repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: false)

        puts "Loading contents into #{repo.nwo}..."
        ExampleRepositories.example_repo("copilot_prereviews", repo)

        repo
      end

      memoize def monalisa
        Seeds::Objects::User.monalisa
      end

      sig { returns Organization }
      def copilot_business_org
        org_on_copilot_business_name = "copilot-business-org"
        org = Organization.find_by(login: org_on_copilot_business_name)
        if org
          puts "➡️ Found @#{org}"
        else
          puts "➡️ Creating @#{org_on_copilot_business_name}..."
          org = FactoryBot.create(:copilot_for_business_enabled_organization,
            name: org_on_copilot_business_name,
            billing_email: monalisa.emails.first.email,
            admins: [monalisa],
          )
        end

        begin
          org.business.add_owner(monalisa, actor: monalisa)
        rescue Exception # rubocop:todo Lint/RescueException
        end

        # enable Bing skill at the business level
        b = ::Copilot::Business.new(org.business)
        b.copilot_for_dotcom_enabled!
        b.bing_github_chat_enabled!
        b.beta_features_github_chat_enabled!

        # enable additional models
        b.o1_enabled!

        begin
          FactoryBot.create(:copilot_seat_assignment, organization: org, assignable: monalisa)
        rescue Exception # rubocop:todo Lint/RescueException
        end
        org
      end

      memoize def copilot_enterprise_org
        org_on_copilot_enterprise_name = "copilot-enterprise-org"
        org = Organization.find_by(login: org_on_copilot_enterprise_name)
        if org
          puts "➡️ Found @#{org}"
        else
          puts "➡️ Creating @#{org_on_copilot_enterprise_name}..."
          org = FactoryBot.create(:copilot_feature_enabled_enterprise_organization,
            :copilot_plan_enterprise,
            id: 2206, # to match https://github.com/github/copilot-api/blob/8a68ab88b9fdf79dd4f094136942ebe62ac1e1ad/pkg/kb/store/memory.go#L36
            name: org_on_copilot_enterprise_name,
            billing_email: monalisa.emails.first.email,
            admins: [monalisa],
          )
        end

        begin
          org.business.add_owner(monalisa, actor: monalisa)
        rescue Exception # rubocop:todo Lint/RescueException
        end

        # enable Bing skill at the business level
        b = ::Copilot::Business.new(org.business)
        b.copilot_for_dotcom_enabled!
        b.bing_github_chat_enabled!
        b.beta_features_github_chat_enabled!
        enable_free_billing_workaround(org.business)

        # enable additional models
        b.o1_enabled!

        # enable MCP
        b.mcp_enabled!

        # enable haiku 4.5
        b.configuration.bento_enabled!

        # enable Gpt 5
        b.configuration.obmb_enabled!

        begin
          FactoryBot.create(:copilot_seat_assignment, organization: org, assignable: monalisa)
        rescue Exception # rubocop:todo Lint/RescueException
        end

        org
      end

      # enable :copilot_for_business_free to get around Copilot::Billable#copilot_billable? check in dev.
      # Without this things like the http://github.localhost/organizations/copilot-enterprise-org/settings/copilot/policies will simply redirect
      # to the seat assignments page.
      def enable_free_billing_workaround(business)
        Seeds::Objects::FeatureFlag.enable(feature_flag: :copilot_for_business_free, actor: business)
      end

      sig { returns Repository }
      def copilot_enterprise_repo
        repo_name = "copilot-enterprise-repo"
        repo = copilot_enterprise_org.repositories.find_by(name: repo_name)
        if repo
          puts "➡️ Found repository #{repo.nwo}"
        else
          puts "➡️ Creating repository #{copilot_enterprise_org}/#{repo_name}..."
          repo = FactoryBot.create(:repository, name: repo_name, owner: copilot_enterprise_org)
        end

        ExampleRepositories.example_repo("copilot_prereviews", repo)

        ## Create ignore rules for this repo
        ::Copilot::ContentExclusionConfiguration.create(
          resource: repo,
          updated_by: monalisa,
          resource_type: "Repository",
          document: "- /**/*.exclude"
        )
        repo
      end

      sig { void }
      def create_indexed_repositories
        # Note - .find_or_create_by is not recommended for production code, because it can lead to race conditions between replicas.
        # But it should be just fine for our seed file.
        CopilotIndexedRepositories.find_or_create_by(repository_id: copilot_enterprise_org.id, organization_id: copilot_enterprise_org.id)
      end


      sig { void }
      def enable_modelpicker
        puts "Enabling model picker feature flags..."
        feature_flags = %w(
          copilot_api_enable_model_o1_preview_squirrel
          copilot_api_enable_model_o1_mini_squirrel
          copilot_byom_g2
        )
        feature_flags_to_disable = [
          "byom-filter",
          "copilot_api_azure_only_models_filter" # If this flag is enabled, non-Azure hosted models (haiku 4.5 and friends) won't show up in model picker
        ]
        feature_flags.each do |feature_flag|
          puts "Enabling #{feature_flag} feature..."
          Seeds::Objects::FeatureFlag.enable(feature_flag: feature_flag)
        end
        feature_flags_to_disable.each do |feature_flag|
          puts "Disabling #{feature_flag} feature..."
          Seeds::Objects::FeatureFlag.disable(feature_flag: feature_flag)
        end
        puts "➡️ Done enabling model picker feature feature flags!"

      end
    end
  end
end
