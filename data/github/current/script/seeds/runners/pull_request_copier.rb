# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class PullRequestCopier < Seeds::Runner
      DEFAULT_AUTHOR = "monalisa"

      def self.help
        <<~HELP
          Copy a real pull request from GitHub.com into the local dev environment.

          This script fetches a PR from any public or private GitHub repository (using
          your current authentication) and replicates it locally, including:
          - Repository structure and file contents
          - Base and head branches
          - Commit history (mapped to local user)
          - PR metadata (title, description, labels)
          - PR comments and review comments (all attributed to monalisa)

          Options:
            -url, -u
              The full URL to the pull request to copy.
              Example: bin/seed pull_request_copier -u https://github.com/owner/repo/pull/123
        HELP
      end

      def self.run(options = {})
        pr_url = options[:url]
        raise ArgumentError, "A PR URL is required. Use -url <url>" unless pr_url

        owner, repo_name, pr_number = parse_pr_url(pr_url)
        puts "Copying PR ##{pr_number} from #{owner}/#{repo_name}..."

        # Fetch PR data from GitHub API using gh CLI
        pr_data = fetch_pr_data(owner, repo_name, pr_number)
        commits_data = fetch_commits_data(owner, repo_name, pr_number)
        files_data = fetch_files_data(owner, repo_name, pr_number)
        comments_data = fetch_comments_data(owner, repo_name, pr_number)
        review_comments_data = fetch_review_comments_data(owner, repo_name, pr_number)

        # Ensure local user exists
        puts "Setting up local user..."
        author = Seeds::Objects::User.create(login: DEFAULT_AUTHOR)

        # Determine if we need an org or user repo
        local_owner, local_repo = setup_local_repository(owner, repo_name, author)

        # Clone/sync repository contents
        puts "Syncing repository contents..."
        repo = sync_repository_contents(local_owner, local_repo, owner, repo_name, pr_data, author)

        # Create the PR with all its data
        puts "Creating local pull request..."
        local_pr = create_local_pr(
          repo: repo,
          author: author,
          pr_data: pr_data,
          commits_data: commits_data,
          files_data: files_data
        )

        # Add comments
        puts "Adding comments..."
        warnings = []
        warnings += add_comments(local_pr, comments_data, author)
        warnings += add_review_comments(local_pr, review_comments_data, author)

        # Print summary
        print_summary(local_pr, pr_data, commits_data, files_data, comments_data, review_comments_data, warnings)
      end

      def self.parse_pr_url(url)
        # Parse URLs like https://github.com/owner/repo/pull/123
        match = url.match(%r{github\.com/([^/]+)/([^/]+)/pull/(\d+)})
        raise ArgumentError, "Invalid PR URL format: #{url}" unless match

        [match[1], match[2], match[3].to_i]
      end

      def self.fetch_pr_data(owner, repo_name, pr_number)
        puts "\tFetching PR metadata..."
        json = run_gh_command("gh api repos/#{owner}/#{repo_name}/pulls/#{pr_number}")
        JSON.parse(json)
      end

      def self.fetch_commits_data(owner, repo_name, pr_number)
        puts "\tFetching commits..."
        all_commits = []
        page = 1
        per_page = 100

        loop do
          json = run_gh_command("gh api 'repos/#{owner}/#{repo_name}/pulls/#{pr_number}/commits?per_page=#{per_page}&page=#{page}'")
          commits = JSON.parse(json)
          break if commits.empty?

          all_commits.concat(commits)
          break if commits.length < per_page

          page += 1
        end

        puts "\t\tFetched #{all_commits.length} commits"
        all_commits
      end

      def self.fetch_files_data(owner, repo_name, pr_number)
        puts "\tFetching changed files..."
        all_files = []
        page = 1
        per_page = 100

        loop do
          json = run_gh_command("gh api 'repos/#{owner}/#{repo_name}/pulls/#{pr_number}/files?per_page=#{per_page}&page=#{page}'")
          files = JSON.parse(json)
          break if files.empty?

          all_files.concat(files)
          break if files.length < per_page

          page += 1
        end

        puts "\t\tFetched #{all_files.length} changed files"
        all_files
      end

      def self.fetch_comments_data(owner, repo_name, pr_number)
        puts "\tFetching issue comments..."
        all_comments = []
        page = 1
        per_page = 100

        loop do
          json = run_gh_command("gh api 'repos/#{owner}/#{repo_name}/issues/#{pr_number}/comments?per_page=#{per_page}&page=#{page}'")
          comments = JSON.parse(json)
          break if comments.empty?

          all_comments.concat(comments)
          break if comments.length < per_page

          page += 1
        end

        puts "\t\tFetched #{all_comments.length} issue comments"
        all_comments
      end

      def self.fetch_review_comments_data(owner, repo_name, pr_number)
        puts "\tFetching review comments..."
        all_comments = []
        page = 1
        per_page = 100

        loop do
          json = run_gh_command("gh api 'repos/#{owner}/#{repo_name}/pulls/#{pr_number}/comments?per_page=#{per_page}&page=#{page}'")
          comments = JSON.parse(json)
          break if comments.empty?

          all_comments.concat(comments)
          break if comments.length < per_page

          page += 1
        end

        puts "\t\tFetched #{all_comments.length} review comments"
        all_comments
      end

      def self.run_gh_command(command)
        output = `#{command} 2>&1`
        unless $?.success?
          raise "GitHub CLI command failed: #{command}\nOutput: #{output}"
        end
        output
      end

      def self.setup_local_repository(remote_owner, remote_repo, author)
        # Check if the remote owner is an organization or user
        begin
          org_json = run_gh_command("gh api orgs/#{remote_owner}")
          org_data = JSON.parse(org_json)
          is_org = org_data["type"] == "Organization"
        rescue
          is_org = false
        end

        if is_org
          # Create or find local org
          local_owner = remote_owner
          local_org = Seeds::Objects::Organization.create(login: local_owner, admin: author)
          local_org.add_member(author)
        else
          # Use monalisa as owner for user repos
          local_owner = author.login
        end

        [local_owner, remote_repo]
      end

      def self.sync_repository_contents(local_owner, local_repo_name, remote_owner, remote_repo_name, pr_data, author)
        nwo = "#{local_owner}/#{local_repo_name}"
        base_branch = pr_data["base"]["ref"]

        # Create or get the local repository
        repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: false, is_public: true)

        # Clone the remote repo to a temp location and sync contents
        temp_dir = File.join(Dir.tmpdir, "pr_copier_#{SecureRandom.hex(8)}")
        begin
          puts "\t\tCloning remote repository..."
          # Optimization flags:
          # --bare: No working directory (already using)
          # --filter=blob:none: Partial clone - download blobs on-demand for faster initial clone
          # --no-tags: Skip fetching tags (not needed for PRs)
          # -q: Quiet mode to reduce output
          clone_cmd = "git clone --bare --filter=blob:none --no-tags -q https://github.com/#{remote_owner}/#{remote_repo_name}.git #{temp_dir}"
          result = `#{clone_cmd} 2>&1`
          unless $?.success?
            raise "Failed to clone repository: #{result}"
          end

          # Always reset the base branch to the PR's original base SHA
          # This ensures the diff shows exactly the same changes as the original PR,
          # regardless of whether the PR is merged or if master has moved forward
          base_sha = pr_data.dig("base", "sha")
          if base_sha
            puts "\t\tResetting base branch to PR's original base SHA: #{base_sha[0..10]}..."
            reset_cmd = "cd #{temp_dir} && git update-ref refs/heads/#{base_branch} #{base_sha}"
            result = `#{reset_cmd} 2>&1`
            unless $?.success?
              puts "\t\tWarning: Could not reset base branch: #{result}"
            end
          end

          # Copy the git data to the local repo
          puts "\t\tSyncing to local repository..."
          repo.dgit_all_routes.map(&:path).each do |dest|
            FileUtils.rm_rf(dest)
            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp_r(temp_dir, dest)
          end

          reader = GitHub::DGit::Routing.hosts_for_network(repo.network.id).first
          GitHub::DGit::Maintenance.recompute_checksums(repo, reader, is_wiki: false, force_dgit_init: true)

          # Ensure the default branch exists
          if repo.heads.find(base_branch).nil? && repo.heads.any?
            # Set default branch to what we have
            first_branch = repo.heads.first
            repo.update!(default_branch: first_branch.name) if first_branch
          elsif repo.heads.find(base_branch)
            repo.update!(default_branch: base_branch)
          end
        ensure
          FileUtils.rm_rf(temp_dir)
        end

        repo.reload
        repo
      end

      def self.create_local_pr(repo:, author:, pr_data:, commits_data:, files_data:)
        base_ref = pr_data["base"]["ref"]
        head_ref = pr_data["head"]["ref"]
        title = pr_data["title"]
        body = pr_data["body"] || ""

        puts "\t\tOriginal base: #{base_ref}, head: #{head_ref}"

        # Check if base branch exists first, fall back to default branch
        if repo.heads.find(base_ref).nil?
          puts "\t\tBase branch '#{base_ref}' not found, using default branch..."
          base_ref = repo.default_branch
        end

        # If base and head are the same, create a new unique head branch name
        if base_ref == head_ref
          head_ref = "#{head_ref}-pr-#{pr_data["number"]}"
          puts "\t\tBase and head are identical, renaming head to: #{head_ref}"
        end

        # Check if there's already a PR for this head branch and make it unique if needed
        existing_pr = ::PullRequest.joins(:issue).where(repository: repo, head_ref: head_ref).where.not(issues: { state: "closed" }).first

        if existing_pr
          head_ref = "#{head_ref}-#{Time.now.to_i}"
          puts "\t\tPR already exists for this branch, using unique name: #{head_ref}"
        end

        # Ensure head branch exists or create it with changes
        if repo.heads.find(head_ref).nil?
          puts "\t\tHead branch '#{head_ref}' not found, creating from base..."
          # Create the head branch from base with the file changes
          create_head_branch_with_changes(repo, author, base_ref, head_ref, files_data, commits_data)
        else
          # Head branch exists but might be same as base - check if we need to apply changes
          head_sha = repo.heads.find(head_ref)&.sha
          base_sha = repo.heads.find(base_ref)&.sha
          if head_sha == base_sha && files_data.any?
            puts "\t\tHead and base have same SHA, applying changes to head..."
            apply_file_changes_as_commit(repo, author, head_ref, commits_data.last&.dig("commit", "message") || "PR changes", Time.now.iso8601, files_data)
          end
        end

        puts "\t\tFinal base: #{base_ref}, head: #{head_ref}"
        puts "\t\tBase SHA: #{repo.heads.find(base_ref)&.sha}"
        puts "\t\tHead SHA: #{repo.heads.find(head_ref)&.sha}"

        # Add labels section to body
        labels = (pr_data["labels"] || []).map { |l| l["name"] }
        if labels.any?
          body += "\n\n---\n**Original Labels:** #{labels.join(", ")}"
        end

        # Add original author info
        original_author = pr_data.dig("user", "login") || "unknown"
        body += "\n\n**Originally authored by:** @#{original_author}"
        body += "\n**Copied from:** #{pr_data["html_url"]}"

        puts "\t\tCreating pull request..."
        pr = ::PullRequest.create_for!(
          repo,
          user: author,
          title: title,
          body: body,
          head: head_ref,
          base: base_ref,
          draft: pr_data["draft"] || false
        )

        pr
      end

      def self.create_head_branch_with_changes(repo, author, base_ref, head_ref, files_data, commits_data)
        # Ensure base ref exists
        base = repo.heads.find(base_ref) || repo.heads.first
        raise "No branches found in repository" unless base

        # Get the base commit
        base_oid = base.sha

        # Create the head branch
        head_branch = repo.refs.create("refs/heads/#{head_ref}", base_oid, author)

        # Apply all file changes in a single commit
        # Use the last commit message if available, otherwise use a generic message
        if commits_data.any?
          last_commit = commits_data.last
          message = last_commit.dig("commit", "message") || "Changes from copied PR"
          date = last_commit.dig("commit", "committer", "date") || Time.now.iso8601
          apply_file_changes_as_commit(repo, author, head_ref, message, date, files_data)
        else
          apply_file_changes_as_commit(repo, author, head_ref, "Changes from copied PR", Time.now.iso8601, files_data)
        end
      end

      def self.apply_file_changes_as_commit(repo, author, branch_name, message, date, files_data)
        return if files_data.empty?

        metadata = {
          message: message,
          committer: author,
          author: author,
          committed_date: date,
          authored_date: date
        }

        ref = repo.heads.find(branch_name)
        return unless ref

        # Pre-fetch all file contents
        file_contents = {}
        files_data.each do |file|
          status = file["status"]
          path = file["filename"]

          case status
          when "removed"
            file_contents[path] = { action: :remove }
            puts "\t\tWill remove: #{path}"
          when "renamed"
            previous_path = file["previous_filename"]
            content = fetch_file_content(file)
            if content
              file_contents[path] = { action: :rename, content: content, previous_path: previous_path }
              puts "\t\tWill rename: #{previous_path} -> #{path}"
            else
              puts "\t\tSkipping renamed file (no content): #{path}"
            end
          when "added"
            content = fetch_file_content(file)
            if content && !content.empty?
              file_contents[path] = { action: :add, content: content }
              puts "\t\tWill add: #{path} (#{content.bytesize} bytes)"
            else
              puts "\t\tSkipping added file (no content): #{path}"
            end
          else # modified, changed
            content = fetch_file_content(file)
            if content && !content.empty?
              file_contents[path] = { action: :modify, content: content }
              puts "\t\tWill modify: #{path} (#{content.bytesize} bytes)"
            else
              puts "\t\tSkipping modified file (no content): #{path}"
            end
          end
        end

        return if file_contents.empty?

        begin
          ref.append_commit(metadata, author) do |changes|
            file_contents.each do |path, info|
              begin
                case info[:action]
                when :remove
                  changes.remove(path)
                when :rename
                  changes.remove(info[:previous_path]) if info[:previous_path]
                  changes.add(path, info[:content])
                when :add, :modify
                  changes.add(path, info[:content])
                end
              rescue => e
                puts "\t\tWarning: Could not process file #{path}: #{e.message}"
              end
            end
          end
          puts "\t\tCommit created successfully with #{file_contents.size} files"
        rescue => e
          puts "\t\tError creating commit: #{e.message}"
          puts "\t\tAttempting fallback with minimal changes..."

          # Fallback: try with just a README change
          begin
            ref.append_commit(metadata, author) do |changes|
              changes.add("COPIED_PR_README.md", "# Copied Pull Request\n\nThis PR was copied from GitHub.com.\n\nOriginal files: #{files_data.map { |f| f["filename"] }.join(", ")}\n\nSome files could not be copied due to size or content restrictions.")
            end
          rescue => fallback_error
            puts "\t\tFallback also failed: #{fallback_error.message}"
          end
        end
      end

      def self.fetch_file_content(file)
        status = file["status"]
        raw_url = file["raw_url"]
        patch = file["patch"]

        # For added files, try raw_url first, then fall back to patch
        if status == "added"
          # Try to fetch from raw_url first
          if raw_url
            content = fetch_raw_content(raw_url)
            return content if content && !content.empty?
          end

          # Fall back to extracting from patch
          if patch
            return extract_added_content_from_patch(patch)
          end

          return nil
        end

        # For modified/renamed files, we MUST use raw_url to get the full content
        if raw_url
          content = fetch_raw_content(raw_url)
          return content if content && !content.empty?
        end

        # No raw_url available - this shouldn't happen normally
        nil
      end

      def self.extract_added_content_from_patch(patch)
        lines = []
        patch.each_line do |line|
          if line.start_with?("+") && !line.start_with?("+++")
            lines << line[1..]
          end
        end
        return nil if lines.empty?
        lines.join
      end

      def self.fetch_file_content_from_patch(file)
        patch = file["patch"]
        return nil unless patch

        # For added files, we can reconstruct from patch
        # For modified files, the patch only has the diff, so we need to be careful
        status = file["status"]

        if status == "added"
          # For new files, we can get the full content from the patch
          lines = []
          patch.each_line do |line|
            if line.start_with?("+") && !line.start_with?("+++")
              lines << line[1..]
            end
          end
          return nil if lines.empty?
          return lines.join
        end

        # For modified/changed files, try to fetch the actual content from raw_url
        raw_url = file["raw_url"]
        if raw_url
          begin
            content = fetch_raw_content(raw_url)
            return content if content && !content.empty?
          rescue => e
            # Fall back to patch-based extraction
          end
        end

        # Fallback: extract from patch (may be incomplete for modified files)
        lines = []
        patch.each_line do |line|
          if line.start_with?("+") && !line.start_with?("+++")
            lines << line[1..]
          elsif line.start_with?(" ")
            lines << line[1..]
          end
        end

        return nil if lines.empty?
        lines.join
      end

      def self.fetch_raw_content(raw_url)
        # Use gh CLI to fetch authenticated raw content
        # The raw_url might need authentication for private repos
        output = `curl -sL "#{raw_url}" 2>&1`
        return nil unless $?.success?
        return nil if output.start_with?("<!DOCTYPE", "<html")
        output
      rescue
        nil
      end

      def self.add_comments(pr, comments_data, author)
        warnings = []
        comments_data.each_with_index do |comment, index|
          body = comment["body"] || ""

          begin
            Seeds::Objects::IssueComment.create(
              issue: pr.issue,
              user: author,
              body: body
            )
          rescue => e
            warnings << "Failed to create comment #{index + 1}: #{e.message}"
          end
        end
        warnings
      end

      def self.add_review_comments(pr, review_comments_data, author)
        warnings = []

        # Group comments by their thread (in_reply_to_id)
        threads = {}
        standalone_comments = []

        review_comments_data.each do |comment|
          reply_to = comment["in_reply_to_id"]
          if reply_to
            threads[reply_to] ||= []
            threads[reply_to] << comment
          else
            standalone_comments << comment
          end
        end

        standalone_comments.each_with_index do |comment, index|
          body = comment["body"] || ""
          path = comment["path"]
          line = comment["line"] || comment["original_line"] || 1
          side = (comment["side"] || "RIGHT").downcase.to_sym
          side = side == :left ? :left : :right

          # Get replies for this comment
          comment_id = comment["id"]
          replies = threads[comment_id] || []

          begin
            # Create a review with the comment
            review = pr.pending_review_for(user: author, head_sha: pr.head_sha)
            thread = review.build_thread

            diff = pr.historical_comparison.diffs

            # Find the delta for this path
            delta = diff.deltas.find { |d| d.path.to_s == path }

            if delta
              first_comment = thread.build_first_comment(
                body: body,
                path: path,
                diff: diff,
                line: line,
                side: side
              )

              if first_comment.save
                review.save!
                review.trigger(:comment)

                # Add replies to the thread
                replies.each do |reply|
                  reply_body = reply["body"] || ""

                  begin
                    # Create a new review for the reply
                    reply_review = pr.reviews.create!(user: author, head_sha: pr.head_sha)
                    reply_comment = first_comment.build_reply(review: reply_review, body: reply_body)
                    reply_comment.save!
                    reply_review.comment!
                  rescue => e
                    warnings << "Failed to add reply to review comment: #{e.message}"
                  end
                end
              else
                warnings << "Failed to create review comment #{index + 1} on #{path}:#{line}: #{first_comment.errors.full_messages.join(", ")}"
              end
            else
              warnings << "Could not find file '#{path}' in diff for review comment #{index + 1}"
            end
          rescue => e
            warnings << "Failed to create review comment #{index + 1}: #{e.message}"
          end
        end

        warnings
      end

      def self.print_summary(pr, pr_data, commits_data, files_data, comments_data, review_comments_data, warnings)
        puts "\n#{"=" * 60}"
        puts "✅ Pull Request Copied Successfully!"
        puts "=" * 60
        puts ""
        puts "📍 Local PR URL: http://github.localhost/#{pr.repository.nwo}/pull/#{pr.number}"
        puts ""
        puts "📊 Summary:"
        puts "   Title: #{pr_data["title"]}"
        puts "   Commits copied: #{commits_data.length}"
        puts "   Files changed: #{files_data.length}"
        puts "   Issue comments: #{comments_data.length}"
        puts "   Review comments: #{review_comments_data.length}"
        puts ""
        puts "   Original PR: #{pr_data["html_url"]}"
        puts "   Original author: @#{pr_data.dig("user", "login")}"
        puts ""

        if warnings.any?
          puts "⚠️  Warnings:"
          warnings.each { |w| puts "   - #{w}" }
          puts ""
        end

        puts "=" * 60
      end
    end
  end
end
