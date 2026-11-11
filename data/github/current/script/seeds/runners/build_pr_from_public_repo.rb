# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class BuildPrFromPublicRepo < Seeds::Runner
      DEFAULT_AUTHOR = "monalisa"
      DEFAULT_REPO_NAME = "smile"
      DEFAULT_REVIEWERS = %w(collaborator).freeze
      DEFAULT_NUM_COMMENTS = 20

      # Default source repo (zustand) - can be overridden with options
      DEFAULT_SOURCE_OWNER = "pmndrs"
      DEFAULT_SOURCE_REPO = "zustand"
      DEFAULT_BASE_COMMIT = "382eeaca0a3040e1e4c41c8981becbdf18fa7a0c"
      DEFAULT_HEAD_COMMIT = "267a57c32c24822ecb66418ecdbcf05476313edd"

      def self.help
        <<~HELP
        Seed a pull request by cloning files from a public GitHub repository.

        By default, this clones the zustand open source repo, but you can specify
        any public GitHub repository with custom base and head commits.

        This creates a realistic PR by:
        - Fetching files from the source repo at the base commit
        - Fetching files from the source repo at the head commit
        - Creating a PR between the two branches
        - Adding review comments at random positions in the diff

        This provides a realistic PR for testing PR page performance with
        real-world file types and changes.

        Options:
          --author, -u
            String name of the pull request author.
            Defaults to #{DEFAULT_AUTHOR}.
            Example: bin/seed build_pr_from_public_repo -u octocat
          --nwo, -r
            String "name with owner" of the pull request base repository (where PR is created).
            Defaults to #{DEFAULT_AUTHOR}/#{DEFAULT_REPO_NAME}.
            Example: bin/seed build_pr_from_public_repo -r octocat/octorepo
          --reviewers, -v
            Array of reviewer logins.
            Defaults to #{DEFAULT_REVIEWERS}.
            Example: bin/seed build_pr_from_public_repo -v reviewer1 reviewer2
          --num-comments, -c
            Integer number of review comments to add.
            Defaults to #{DEFAULT_NUM_COMMENTS}.
            Example: bin/seed build_pr_from_public_repo -c 30
          --draft, -d
            Boolean flag to create the PR as a draft.
            Defaults to false.
            Example: bin/seed build_pr_from_public_repo -d
          --source-owner
            String owner of the source GitHub repository to clone from.
            Defaults to #{DEFAULT_SOURCE_OWNER}.
            Example: bin/seed build_pr_from_public_repo --source-owner facebook
          --source-repo
            String name of the source GitHub repository to clone from.
            Defaults to #{DEFAULT_SOURCE_REPO}.
            Example: bin/seed build_pr_from_public_repo --source-repo react
          --base-commit
            String commit SHA for the base branch.
            Defaults to #{DEFAULT_BASE_COMMIT}.
            Example: bin/seed build_pr_from_public_repo --base-commit abc123
          --head-commit
            String commit SHA for the head branch.
            Defaults to #{DEFAULT_HEAD_COMMIT}.
            Example: bin/seed build_pr_from_public_repo --head-commit def456
        HELP
      end

      def self.run(options = {})
        require "net/http"
        require "json"
        require "uri"
        require "base64"

        puts "Setting up users and repos..."

        # Ensure PR author exists
        author_login = options[:author] || DEFAULT_AUTHOR
        puts "\tFinding or creating PR author #{author_login}..."
        author = Seeds::Objects::User.create(login: author_login)

        # Ensure PR reviewers exist
        reviewer_logins = options[:reviewers] || DEFAULT_REVIEWERS
        reviewers = reviewer_logins.map do |reviewer_login|
          puts "\tFinding or creating PR reviewer #{reviewer_login}..."
          Seeds::Objects::User.create(login: reviewer_login)
        end
        reviewer_user_ids = reviewers.map(&:id)

        # Ensure repo exists
        nwo = options[:nwo] || "#{author_login}/#{DEFAULT_REPO_NAME}"
        puts "\tFinding or creating repo #{nwo}..."
        repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: true, is_public: true)

        # Ensure all users have write permissions
        all_users = [author] | reviewers
        all_users.each do |user|
          puts "\tAdding #{user} to #{repo.nwo} as member with write permissions..."
          repo.add_member(user)
        end

        # Get options
        num_comments = options[:num_comments] || DEFAULT_NUM_COMMENTS
        draft = options[:draft] || false
        source_owner = options[:source_owner] || DEFAULT_SOURCE_OWNER
        source_repo = options[:source_repo] || DEFAULT_SOURCE_REPO
        base_commit = options[:base_commit] || DEFAULT_BASE_COMMIT
        head_commit = options[:head_commit] || DEFAULT_HEAD_COMMIT

        puts "\nCreating PR from #{source_owner}/#{source_repo} in #{repo.nwo}..."
        pull = seed_external_repo_pr(
          repo: repo,
          author: author,
          reviewer_user_ids: reviewer_user_ids,
          num_comments: num_comments,
          draft: draft,
          source_owner: source_owner,
          source_repo: source_repo,
          base_commit: base_commit,
          head_commit: head_commit,
        )

        if pull
          puts "\nSuccessfully created PR!"
          puts "  PR ##{pull.number}: #{pull.title}"
          puts "  URL: http://github.localhost/#{repo.nwo}/pull/#{pull.number}"
        else
          puts "\nFailed to create PR. Check the output above for errors."
        end
      end

      def self.seed_external_repo_pr(repo:, author:, reviewer_user_ids:, source_owner:, source_repo:, base_commit:, head_commit:, num_comments: DEFAULT_NUM_COMMENTS, draft: false)
        base_branch_name = "#{source_repo}-base-#{SecureRandom.hex(4)}"
        head_branch_name = "#{source_repo}-head-#{SecureRandom.hex(4)}"

        puts "\tFetching #{source_owner}/#{source_repo} files at commit #{base_commit[0..7]}..."
        base_files = fetch_github_tree_files(
          owner: source_owner,
          repo_name: source_repo,
          ref: base_commit
        )

        if base_files.empty?
          puts "\tError: Could not fetch base files from #{source_owner}/#{source_repo}"
          puts "\tMake sure you have a GITHUB_TOKEN environment variable set for higher rate limits."
          return nil
        end

        puts "\tFetched #{base_files.size} files for base branch"
        puts "\tCommitting base files to branch #{base_branch_name}..."

        base_commit_obj = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Import #{source_owner}/#{source_repo} at #{base_commit[0..7]}",
          files: base_files
        )

        puts "\tFetching #{source_owner}/#{source_repo} files at commit #{head_commit[0..7]}..."
        head_files = fetch_github_tree_files(
          owner: source_owner,
          repo_name: source_repo,
          ref: head_commit
        )

        if head_files.empty?
          puts "\tError: Could not fetch head files from #{source_owner}/#{source_repo}"
          puts "\tMake sure you have a GITHUB_TOKEN environment variable set for higher rate limits."
          return nil
        end

        puts "\tFetched #{head_files.size} files for head branch"
        puts "\tCreating head branch #{head_branch_name}..."

        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit_obj.oid, author)

        puts "\tCommitting head files..."
        head_ref.append_commit({ message: "Update #{source_owner}/#{source_repo} to #{head_commit[0..7]}", committer: author, author: author }, author) do |changes|
          # Find files to add or modify
          head_files.each do |path, content|
            changes.add(path, content)
          end

          # Find files to remove (in base but not in head)
          base_files.each_key do |path|
            unless head_files.key?(path)
              changes.remove(path)
            end
          end
        end

        puts "\tOpening PR..."
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR from #{source_owner}/#{source_repo} (#{base_commit[0..7]}...#{head_commit[0..7]})",
          body: <<~BODY,
            This PR contains changes from [#{source_owner}/#{source_repo}](https://github.com/#{source_owner}/#{source_repo}).

            ## Changes

            This includes all changes made to the repository between the two commits.

            - Base: https://github.com/#{source_owner}/#{source_repo}/tree/#{base_commit}
            - Head: https://github.com/#{source_owner}/#{source_repo}/tree/#{head_commit}

            ## Files Changed

            - Files in base: #{base_files.size}
            - Files in head: #{head_files.size}
          BODY
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )

        if num_comments > 0
          puts "\tAdding #{num_comments} review comments at random positions..."
          add_random_review_comments(
            pull: pull,
            head_files: head_files,
            possible_commenter_ids: reviewer_user_ids,
            num_comments: num_comments
          )
        end

        puts "\tCreated PR ##{pull.number}: #{pull.title}"
        pull
      end

      def self.add_random_review_comments(pull:, head_files:, possible_commenter_ids:, num_comments: DEFAULT_NUM_COMMENTS)
        # Get the diff to find valid comment positions (only lines in the diff can be commented on)
        diffs = pull.historical_comparison.diffs

        # Collect all valid positions from the actual diff
        valid_positions = []

        diffs.each do |entry|
          path = entry.path

          # Iterate through each line in the diff entry
          entry.each_line do |line|
            # Only comment on additions (right side) - these have valid line numbers
            next unless line.addition? && line.right && line.right > 0

            valid_positions << {
              path: path,
              line: line.right,
              side: :right
            }
          end
        end

        if valid_positions.empty?
          puts "\t\tNo valid positions found for comments, skipping..."
          return
        end

        puts "\t\tFound #{valid_positions.size} valid diff positions across #{diffs.size} files"

        # Shuffle and pick random positions for comments
        selected_positions = valid_positions.sample(num_comments)

        comments_created = 0
        selected_positions.each_with_index do |position, index|
          begin
            Seeds::Runner::PullRequests.create_pull_request_review_thread(
              pull: pull,
              possible_commenter_ids: possible_commenter_ids,
              position_options: {
                path: position[:path],
                line: position[:line],
                side: position[:side]
              },
              with_suggested_change: index % 4 == 0 # Every 4th comment has a suggestion
            )
            comments_created += 1
          rescue StandardError => e
            puts "\t\tWarning: Could not create comment at #{position[:path]}:#{position[:line]}: #{e.message}"
          end
        end

        puts "\t\tAdded #{comments_created} review comments"
      end

      def self.fetch_github_tree_files(owner:, repo_name:, ref:)
        files = {}

        # Fetch the tree recursively
        tree_url = URI("https://api.github.com/repos/#{owner}/#{repo_name}/git/trees/#{ref}?recursive=1")
        tree_response = make_github_api_request(tree_url)

        return files unless tree_response && tree_response["tree"]

        # Filter to only blob (file) entries, skip directories
        blobs = tree_response["tree"].select { |item| item["type"] == "blob" }

        puts "\t\tFound #{blobs.size} files to fetch..."

        # Fetch each file's content
        # Limit to reasonable number of files to avoid rate limiting
        blobs_to_fetch = blobs.first(500)
        blobs_to_fetch.each_with_index do |blob, index|
          path = blob["path"]

          # Skip binary files and large files
          next if binary_file?(path)
          next if blob["size"] && blob["size"] > 500_000 # Skip files > 500KB

          content = fetch_file_content(owner: owner, repo_name: repo_name, path: path, ref: ref)
          if content
            files[path] = content
          end

          # Progress indicator
          if (index + 1) % 50 == 0
            puts "\t\t\tFetched #{index + 1}/#{blobs_to_fetch.size} files..."
          end
        end

        files
      end

      def self.fetch_file_content(owner:, repo_name:, path:, ref:)
        url = URI("https://api.github.com/repos/#{owner}/#{repo_name}/contents/#{path}?ref=#{ref}")
        response = make_github_api_request(url)

        return nil unless response

        if response["encoding"] == "base64" && response["content"]
          begin
            Base64.decode64(response["content"])
          rescue StandardError
            nil
          end
        else
          response["content"]
        end
      end

      def self.make_github_api_request(url)
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Get.new(url)
        request["Accept"] = "application/vnd.github.v3+json"
        request["User-Agent"] = "GitHub-Seeds-Script"

        # Use GITHUB_TOKEN if available for higher rate limits
        if ENV["GITHUB_TOKEN"]
          request["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}"
        end

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(T.must(response.body))
        else
          puts "\t\t\tWarning: API request failed for #{url.path}: #{response.code}"
          nil
        end
      rescue StandardError => e
        puts "\t\t\tWarning: Request error for #{url.path}: #{e.message}"
        nil
      end

      def self.binary_file?(path)
        binary_extensions = %w[
          .png .jpg .jpeg .gif .ico .svg .webp
          .woff .woff2 .ttf .eot .otf
          .zip .tar .gz .rar .7z
          .pdf .doc .docx .xls .xlsx
          .exe .dll .so .dylib
          .mp3 .mp4 .avi .mov .wav
          .bin .dat .db .sqlite
        ]
        ext = File.extname(path).downcase
        binary_extensions.include?(ext)
      end
    end
  end
end
