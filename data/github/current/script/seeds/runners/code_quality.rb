# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CodeQuality < Seeds::Runner
      def self.help
        <<~HELP
        Create a repo with seeded findings for code quality development

        - by default creates new repo (or creates/updates named one)
        - uploads a SARIF file for the repo

        Requires the turboquality repo to be cloned locally. You'll likely need the Twirp
        server to be running later anyway, so the best option is to use the
        script/setup-codespaces-turboquality script.

        HELP
      end

      def self.run(options = {})
        puts "\n"

        print "Enabling code quality feature flags..."
        FeatureFlag.vexi_management.enable_feature_flag(:code_quality)
        FeatureFlag.vexi_management.enable_feature_flag(:code_scanning_suggested_all_queries)
        puts " ✅\n\n"

        @mona = Seeds::Objects::User.monalisa
        @owner = find_owner(options)
        @repo_path = "/workspaces/code-quality-seed-data"
        @git_repo_path = "#{@repo_path}/.git"
        @sarif_path = "#{@repo_path}/analysis.sarif"

        if @owner.organization?
          print "Marking advanced security as purchased..."
          if @owner.business.present?
            @owner.business.mark_advanced_security_as_purchased_for_entity(actor: @owner.admins.first)
          else
            @owner.mark_advanced_security_as_purchased_for_entity(actor: @owner.admins.first)
          end
          puts " ✅\n\n"
        end

        print "Checking for seed data repo..."
        if Dir.exist?("/workspaces/code-quality-seed-data")
          puts " ✅ (already exists)\n\n"
        else
          puts " not found.\n"
          print "Cloning seed data repo..."
          result = system("gh repo clone github/code-quality-seed-data /workspaces/code-quality-seed-data")
          puts result ? " ✅\n\n" : " ❌ (Exit status: #{$?.exitstatus})\n\n"
          return unless result
        end

        print "Creating/updating example repo for code quality..."
        @repo = Seeds::Objects::Repository.restore_premade_repo(
          location_premade_git: @git_repo_path,
          owner_name: @owner.login,
          repo_name: options[:name] || "codequality-repo-with-findings-#{Time.now.to_i}",
          is_public: options[:is_public] || !@owner.organization?,
        )
        puts " ✅\n\n"

        # Restoring a premade repo will in some cases not have the default branch loaded in the call to `@repo.refs`.
        # This causes an issues in this script: Enabling advanced security for an org-owned repository will publish a
        # `github.security_center.v1.SecurityFeatureRepoUpdate` message where the default branch is blank and this
        # will in turn result in the alerts not being shown at the org-level.
        @repo.reload

        if @owner.organization?
          print "Enabling advanced security..."
          @repo.enable_advanced_security(actor: @owner.admins.first)
          puts " ✅\n\n"
        end

        print "Enable CodeQL default setup..."
        auto_codeql = ::CodeScanning::AutoCodeql.new(@repo)
        result = auto_codeql.on_enable(actor: @owner.admins.first, options: { action: :enable, runner_label: "ubuntu-latest" })
        puts result.error? ? " ❌ (#{::CodeScanning::AutoCodeql.error_to_message(result.error)})\n\n" : " ✅\n\n"
        return if result.error?

        print "Enabling code quality for the repo..."
        result = CodeQualityEnablement.new(@repo).on_enable(actor: @mona, options: {})
        puts result.error? ? " ❌ (#{CodeQualityEnablement.error_to_message(result.error)})\n\n" : " ✅\n\n"
        return if result.error?

        print "Loading SARIF file into turboquality..."
        sha = @repo.heads.find(@repo.default_branch.b).sha
        status = Seeds::Runner::CodeQuality.turboquality("-repository_id #{@repo.id} -ref #{@repo.default_branch_ref.qualified_name} -commit_oid #{sha} #{@sarif_path}")
        puts status.success? ? " ✅\n\n" : " ❌ (Exit status: #{status.exitstatus})\n\n"
        return unless status.success?

        print "Building a pull request review..."
        head_ref = @repo.refs.create("refs/heads/branch-#{SecureRandom.hex}", @repo.default_branch_ref.commit.oid, @mona)

        # The supporting files are included using gzip/base64 to avoid code quality linters complaining about them and
        # to keep them local to the seed script.
        # To see the original file, grab the compressed string onto your clipboard and run:
        #   pbpaste | base64 --decode | gunzip
        # To make changes, grab the new file onto your clipboard and run:
        #   pbpaste | gzip | base64 | pbcopy

        commit = Seeds::Objects::Commit.create(
          branch_name: head_ref.name,
          repo: @repo,
          committer: @mona,
          message: "test message",
          files: { "bad_quality.js" => ActiveSupport::Gzip.decompress(Base64.decode64("H4sIAG1POGgAA+2Oy07DMBBF9/mK24pFIqRaPFZFEZsuK76hxrGJi+Np7YnSqMq/4zRAURdIrGDB7GZG99wjBNaaIzj0YMKLZkRqNKTTIZ2lr8C1tgHGHnSECdSA2/BM+1Y6y/0sk7H3Cqb1ii35kbCSLHNbFThmSOMSM+g9SshOWobRrOp8UzPv4lIIfZDNzumFokZUKfloq/LqaKthUzyc8tYgnyXAgl6LBErtHr51bvq+H8b/NpLPU2jILqViTd1odXOhNfYlry/O58rpV56qPjLjKPKRkm8ng8/nTzRBDIUl5rjGJ+MsN+3DN163f9Tr7t/rR173v+z1BjD590jOAwAA")) }
        )

        @repo.add_member(@mona)

        pull_request = PullRequest.create_for!(@repo,
          user: @mona,
          title: "Code quality review (#{head_ref.name})",
          body: "This PR triggers a code quality review.",
          head: head_ref.name,
          base: @repo.default_branch_ref.name,
        )

        sha = commit.sha

        status = Seeds::Runner::CodeQuality.turboquality("-repository_id #{@repo.id} -ref refs/pull/#{pull_request.number}/head -commit_oid #{commit.sha} -") do |stdin|
          stdin << ActiveSupport::Gzip.decompress(Base64.decode64(
            "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"
          ))
        end
        puts status.success? ? " ✅\n\n" : " ❌ (Exit status: #{status.exitstatus})\n\n"
        return unless status.success?

        print "Make sure bin/code-quality-pull-request-analysis-processor is running in order to post the review..."

        puts "\n\nSeeding suggested fixes..."
        status = system("cd ../turboquality; go run script/autofix-seed/main.go --repository_id #{@repo.id}")
        puts status ? " ✅\n\n" : " ❌ (Exit status: #{$?.exitstatus})\n\n"
        return unless status

        puts "\n"
        puts "Your new repository is ready:\n"
        puts "    http://#{GitHub.host_name}/#{@repo.nwo}"
        puts "\n"
      end

      def self.find_owner(options = {})
        return ::Organization.find_by!(login: options[:organization_name]) if options[:organization_name]
        Seeds::Objects::Organization.github
      end

      sig { params(args: String).returns(Process::Status) }
      def self.turboquality(args)
        status = T.let(nil, T.nilable(Process::Status))
        Dir.chdir("/workspaces/turboquality") do
          Open3.popen2e("go run ./cmd/sarif-load #{args}") do |stdin, stdout_stderr, wait_thread|
            Thread.new do
              stdout_stderr.each(&method(:puts))
            end
            yield stdin if block_given?
            stdin.close
            status = T.cast(wait_thread.value, Process::Status)
          end
        end
        T.must(status)
      end
    end
  end
end
