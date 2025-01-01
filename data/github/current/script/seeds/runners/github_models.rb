# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class GitHubModels < Seeds::Runner
      def self.help
        <<~HELP
        Loads the latest models from Azure API and constructs repositories for testing GitHub Models features.
        HELP
      end

      REPO_SPECIFIC_FEATURE_FLAGS = %i(github_models_repo_integration github_models_repo_playground).freeze

      TEST_DATA_PROMPT_YML = <<~YAML
messages:
  - role: system
    content: Summarize the concept provided. Use emoji. You are a helpful model.
  - role: user
    content: 'I want to learn more about {{input}}'
model: gpt-4o
testData:
  - input: subatomic particles
  - input: light-speed travel
YAML

      TEACHER_PROMPT_YML = <<~YAML
messages:
  - role: system
    content: You are a teacher of elementary school children. Use simple language.
  - role: user
    content: 'Explain {{subject}}.'
YAML

      INVALID_PROMPT_YML = <<~YAML
messages:
  - role: system
    content: You are a teacher explaining concepts to children.
  - role: user
    content: 'How does {{input}} work?'
model: gpt-4.1-mini
testData:          # Optional test cases
  - input: test input!  # Input to test with
    expected: expected output # Expected output
  - file://testdata.yaml
YAML

      SOCK_STYLIST_PROMPT_YML = <<~YAML
messages:
  - role: system
    content: >
      You are a cheeky but fashion-conscious sock stylist. Your job is to
      recommend the perfect socks for someone’s day, outfit, and emotional vibe
      from a selection of socks available in this store. It should specify
      whether it is an anklet, crew, or knee-high sock. Be playful, stylish, and
      slightly dramatic. You only recommend one type of sock, but describe it
      vividly.
  - role: user
    content: '{{input}}. Which socks should I buy from your store? '
model: gpt-4o-mini
YAML

      SOCK_HEIGHT_ORACLE_PROMPT_YML = <<~YAML
messages:
  - role: system
    content: >
      You are a wise and slightly mystical oracle who determines the appropriate
      sock height (anklet, crew, or knee-high) based solely on the user's vibe
      for the day. Use poetic or theatrical language to justify your decision,
      even if it's absurd.
  - role: user
    content: '{{input}} What height of socks should I wear?'
model: gpt-4o-mini
testData:
  - input: I'm heading to a job interview and it's raining.
    expected: Knee high
  - input: '"Lazy Sunday at home'
    expected: might not even leave the couch."
  - input: I have a long walk to work and it's chilly this morning.
    expected: Crew
  - input: Going to a concert tonight and I'm feeling dramatic.
    expected: Knee high
  - input: Just running a few errands and it's kind of warm out.
    expected: Anklet
  - input: '"First date tonight'
    expected: but it's super windy."
  - input: Sitting in back-to-back Zoom meetings all day.
    expected: Crew
  - input: '"Going hiking in the mountains'
    expected: weather is cool but sunny."
  - input: '"Running late'
    expected: spilled coffee
  - input: '"Heading to the airport'
    expected: lots of walking and sitting ahead."
  - input: '"Attending a fancy dinner'
    expected: but it's indoors and well-heated."
evaluators:
  - name: crew
    string:
      contains: crew
YAML

      PROMPT_YML_BY_PATH = {
        "with-test-data.prompt.yml" => TEST_DATA_PROMPT_YML,
        "myFavorite.prompt.yml" => TEST_DATA_PROMPT_YML,
        "fun-prompts/some.prompt.yml" => TEST_DATA_PROMPT_YML,
        "fun-prompts/teacher.prompt.yml" => TEACHER_PROMPT_YML,
        "teacher2.prompt.yaml" => TEACHER_PROMPT_YML,
        "fun-prompts/socks/sock-height-oracle.prompt.yaml" => SOCK_HEIGHT_ORACLE_PROMPT_YML,
        "fun-prompts/socks/sock-stylist.prompt.yml" => SOCK_STYLIST_PROMPT_YML,
        "My Best Socks.prompt.yml" => SOCK_STYLIST_PROMPT_YML,
        "SockHeightCalculator.prompt.yaml" => SOCK_HEIGHT_ORACLE_PROMPT_YML,
        "invalid.prompt.yml" => INVALID_PROMPT_YML,
      }.freeze

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def self.run(options = {})
        new.run(options)
      end

      sig { params(options: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def run(options)
        repos = [
          create_private_repo("monalisa/models-stuff"),
          create_private_repo("github/models-stuff"),
        ]
        repos.each { |repo| enable_repo_feature_flags(repo) }
        enable_models_for_business
        run_catalog_sync_job
        make_all_models_visible

        repos.each do |repo|
          commit_and_path = create_prompt_files(repo)
          create_prompt_pull_request(commit_and_path[0], commit_and_path[1], repo) if commit_and_path
        end
      end

      private

      sig { void }
      def make_all_models_visible
        models = ::GitHubModels.domain.models.find_many
        models.each do |model|
          ::GitHubModels.domain.models.update_visibility(model, :visible)
        end
        total = models.size
        units = "model".pluralize(total)
        puts "\nCreated #{total} #{units}!"
      end

      sig { void }
      def run_catalog_sync_job
        puts "\nRunning the Azure catalog sync job..."
        ::GitHubModels::FetchCatalogItemsJob.perform_now
      end

      sig { params(repo: ::Repository).void }
      def enable_repo_feature_flags(repo)
        puts "\nEnabling repository-specific feature flags..."
        REPO_SPECIFIC_FEATURE_FLAGS.each do |feature|
          puts "- Enabling #{feature} for #{repo.name_with_display_owner}..."
          GitHub.flipper[feature].enable(repo)
        end
      end

      sig { void }
      def enable_models_for_business
        user = Seeds::Objects::User.monalisa
        org = ::Organization.find_by_login("github") || Seeds::Objects::Organization.create(login: "github",
          admin: user)
        business = org.business
        biz_success = if business
          business.enable_models_access(user)
        else
          true
        end
        if biz_success && org.enable_models_access(user)
          puts "\nEnabled Models access for @#{org.display_login} business"
        else
          puts "\nFailed to enable Models access for @#{org.display_login} business"
        end
      end

      sig { params(nwo: String).returns(::Repository) }
      def create_private_repo(nwo)
        puts "\nSetting up #{nwo} repository..."
        repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: true, is_public: false)
        puts "Visit #{GitHub.url}/#{repo.name_with_display_owner}"
        repo
      end

      sig { params(repo: ::Repository).returns(T.nilable([::Commit, String])) }
      def create_prompt_files(repo)
        commit_and_path = T.let(nil, T.nilable([::Commit, String]))

        PROMPT_YML_BY_PATH.each do |path, yml_content|
          puts "Creating #{path} in #{repo.name_with_display_owner}..."
          commit = Seeds::Objects::Commit.create(
            repo: repo,
            committer: Seeds::Objects::User.monalisa,
            branch_name: repo.default_branch,
            files: { path => yml_content },
            message: "Add #{path}",
          )
          if commit_and_path.nil? || [true, false].sample
            commit_and_path = [commit, path]
          end
        end

        commit_and_path
      end

      sig { params(base_commit: ::Commit, path: String, repo: ::Repository).returns(T.nilable(::PullRequest)) }
      def create_prompt_pull_request(base_commit, path, repo)
        puts "\nCreating a pull request for #{repo.name_with_display_owner} to modify #{path}..."
        committer = Seeds::Objects::User.monalisa
        new_prompt_content = <<~YAML
messages:
  - role: system
    content: You are an angry chef who speaks only in emoji.
  - role: user
    content: 'Generate a recipe with {{input}} as the main ingredient.'
YAML
        commit = repo.commits.create({ message: "Update #{path}", committer: committer }, base_commit.oid) do |files|
          files.add path, new_prompt_content
        end
        base_ref = repo.default_branch_ref
        branch_name = SecureRandom.hex
        head_ref = repo.refs.create("refs/heads/branch-#{branch_name}", commit.oid, committer)
        pull = ::PullRequest.create_for!(
          repo,
          user: committer,
          title: "Modify #{path}",
          body: "I am altering the prompt. Pray I do not alter it further.",
          head: head_ref.name,
          base: base_ref.name,
        )
        puts "Visit #{GitHub.url}/#{repo.name_with_display_owner}/pull/#{pull.number}"
        pull
      rescue GitRPC::CommandFailed, GitRPC::Failure => err
        puts "Failed to create pull request: #{err}"
        nil
      end
    end
  end
end
