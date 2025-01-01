# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/api_programmatic_grant_helpers"

module IssueCommitMessageSyntax
  class ProgrammaticActorTest < GitHub::TestCase
    include ApiProgrammaticGrantHelpers
    include HydroMessageJobTestHelpers
    include PushTestHelper

    fixtures do
      @user  = create(:user)
      @repo  = create(:private_repository, owner: @user, name: "repo")
      @repo2 = create(:private_repository, owner: @user, name: "repo2")

      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.auto_subscribe = false
      end

      @opened_issue = create :issue, repository: @repo, user: @repo.owner

      @installation_with_read = make_integration_installation(target: @user, permissions: {
        "metadata" => :read, "issues" => :read, "contents" => :read
      })

      @installation_with_write = make_integration_installation(target: @user, permissions: {
        "metadata" => :read, "issues" => :write, "contents" => :write
      })

      @installation_with_read_bot = @installation_with_read.integration.bot
      assert_nil @installation_with_read_bot.installation

      @installation_with_write_bot = @installation_with_write.integration.bot
      assert_nil @installation_with_write_bot.installation

      @repo_2_installation_with_read = make_integration_installation(repository: @repo2, permissions: {
        "metadata" => :read, "issues" => :read, "contents" => :write
      })

      @repo_2_installation_with_write = make_integration_installation(repository: @repo2, permissions: {
        "metadata" => :read, "issues" => :write, "contents" => :write
      })

      @repo_2_installation_with_read_bot = @repo_2_installation_with_read.integration.bot
      assert_nil @repo_2_installation_with_read_bot.installation

      @repo_2_installation_with_write_bot = @repo_2_installation_with_write.integration.bot
      assert_nil @repo_2_installation_with_write_bot.installation
    end

    setup do
      example_repo :issues_and_commit_messages, @repo
      example_repo :issues_and_commit_messages, @repo2

      @opened_issue.open  # ensure the issue is open

      @master = @repo2.heads.read("master")
    end

    def append_commit(ref, committer, message)
      metadata = { message: message, committer: committer }

      ref.append_commit(metadata, committer) do |files|
        files.add("something", "fixedit")
      end
    end

    def post_receive(user, pusher, repo, ref, attrs = {})
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      perform_push_job(pusher, repo, ref, attrs)
    end

    def perform_push_job(pusher, repo, ref, attrs = {})
      sockstat = {
        "user_programmatic_access_id" => attrs[:user_programmatic_access_id],
        "installation_id" => attrs[:installation_id],
        "installation_type" => attrs[:installation_type]
      }

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob, HydroIssuesOnPushJob]) do
        trigger_push_event(
          repo.path,
          pusher.login,
          [["refs/heads/master", GitHub::NULL_OID, ref.target_oid]],
          Time.now,
          nil,
          attrs[:oauth_access_id],
          nil,
          sockstat.symbolize_keys
        )
      end
    end

    def with_no_failbot_reports
      assert_equal 0, Failbot.reports.count
      yield
      assert_equal 0, Failbot.reports.count
    end

    context "closing issues" do
      context "via SSH without authz context" do
        test "SSO protected org with valid user still allows a close" do
          org = create :business_plus_org, admin: @user
          provider = create :organization_saml_provider, organization: org
          create(:external_identity, user: @user, provider: provider)

          provider.enforce!

          org_repo = create(:private_repository, owner: org, from_example: :issues_and_commit_messages)

          opened_org_issue = create(:issue, repository: org_repo, user: org)
          opened_org_issue.open  # ensure the issue is open

          @master = @repo2.heads.read("master")
          append_commit(@master, @user, "fix #{org_repo.name_with_owner}##{opened_org_issue.number}")

          post_receive(@user, @user, @repo2, @master)

          opened_org_issue.reload
          assert opened_org_issue.events.detect { |ev| ev.event == "closed" }
          assert_predicate opened_org_issue, :closed?
        end
      end

      context "server-to-server" do
        test "can close an issue in another repository the installation has access to" do
          append_commit(@master, @installation_with_write_bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @installation_with_write_bot, @repo2, @master, {
            installation_id: @installation_with_write.id,
            installation_type: @installation_with_write.class.to_s
          })

          @opened_issue.reload
          assert_predicate @opened_issue, :closed?

          assert ev = @opened_issue.events.last
          refute ev.async_will_close_subject?.sync

          assert_equal @master.target.oid, ev.commit_id
          assert_equal @installation_with_write_bot, ev.actor
        end

        test "cannot close an issue it does not have direct access to" do
          append_commit(@master, @repo_2_installation_with_write_bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @repo_2_installation_with_write_bot, @repo2, @master, {
            installation_id: @repo_2_installation_with_write.id,
            installation_type: @repo_2_installation_with_write.class.to_s
          })

          @opened_issue.reload
          refute_predicate @opened_issue, :closed?

          assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
        end
      end

      context "scoped server-to-server" do
        test "closes issues it has contents write access to" do
          installation = make_scoped_integration_installation(parent: @installation_with_write, repositories: [@repo, @repo2])
          append_commit(@master, @installation_with_write_bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @installation_with_write_bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload
          assert_predicate @opened_issue, :closed?

          assert ev = @opened_issue.events.last
          refute ev.async_will_close_subject?.sync

          assert_equal @master.target.oid, ev.commit_id
          assert_equal @installation_with_write_bot, ev.actor
        end

        test "cannot close issues it does not have contents write access to" do
          installation = make_scoped_integration_installation(parent: @installation_with_write, repositories: [@repo2])
          append_commit(@master, @installation_with_write_bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @installation_with_write_bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload
          refute_predicate @opened_issue, :closed?

          assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
        end
      end

      context "site scoped server-to-server" do
        # TODO(tarebyte): File an issue because site scoped installations
        # can't reference issues in commit messages.
        test "cannot not close issues it has contents write access to" do
          disable_feature_flag(:disabled_global_apps)

          permissions = { "metadata" => :read, "contents" => :write, "issues" => :write }
          integration = create_unlimited_global_integration(permissions: permissions)

          installation = make_site_scoped_integration_installation(
            integration: integration, target: @user,
            repositories: [@repo, @repo2], permissions: permissions
          )

          bot = integration.bot
          append_commit(@master, bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload

          refute_predicate @opened_issue, :closed?
          assert_predicate @opened_issue.events, :none?
        end

        test "cannot close issues it does not have contents write access to" do
          disable_feature_flag(:disabled_global_apps)

          permissions = { "metadata" => :read, "contents" => :write, "issues" => :write }
          integration = create_unlimited_global_integration(permissions: permissions)

          installation = make_site_scoped_integration_installation(
            integration: integration, target: @user,
            repositories: [@repo2], permissions: permissions
          )

          post_receive(@user, @installation_with_write_bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload

          refute_predicate @opened_issue, :closed?
          assert_predicate @opened_issue.events, :none?
        end
      end

      context "user-to-server" do
        context "can close an issue" do
          test "both the user and app can close" do
            access = @installation_with_write.integration.grant(@user)

            append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
            post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

            @opened_issue.reload
            assert_predicate @opened_issue, :closed?

            assert ev = @opened_issue.events.last
            refute ev.async_will_close_subject?.sync

            assert_equal @master.target.oid, ev.commit_id
            assert_equal @user, ev.actor
          end
        end

        context "cannot close an issue" do
          test "the user can close but the app cannot close" do
            access = @repo_2_installation_with_write.integration.grant(@user)

            append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
            post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

            @opened_issue.reload
            refute_predicate @opened_issue, :closed?

            assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
          end

          test "both the user and app cannot close" do
            rando = create(:user)

            installation = make_integration_installation(repository: @repo2, permissions: { "metadata" => :read })
            access = installation.integration.grant(rando)

            append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
            post_receive(@user, rando, @repo2, @master, { oauth_access_id: access.id })

            @opened_issue.reload
            refute_predicate @opened_issue, :closed?

            assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
          end

          test "the user can close but an app cannot" do
            installation = make_integration_installation(repository: @repo2, permissions: { "metadata" => :read })
            access = installation.integration.grant(@user)

            append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
            post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

            @opened_issue.reload
            refute_predicate @opened_issue, :closed?

            assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
          end

          test "the user and the app can, but the credential is lacking SSO access" do
            disable_feature_flag(:tasklist_block_markdown_at_rest)

            org = create :business_plus_org, admin: @user
            provider = create :organization_saml_provider, organization: org
            create(:external_identity, user: @user, provider: provider)

            provider.enforce!

            integration = @installation_with_write.integration
            org_installation_with_write = make_integration_installation(integration: integration, target: org)

            access = integration.grant(@user)

            org_repo = create(:private_repository, owner: org, from_example: :issues_and_commit_messages)

            opened_org_issue = create(:issue, repository: org_repo, user: org)
            opened_org_issue.open  # ensure the issue is open

            @master = @repo2.heads.read("master")
            append_commit(@master, @user, "fix #{org_repo.name_with_owner}##{opened_org_issue.number}")

            Failbot.backend.reports.clear
            with_no_failbot_reports do
              post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })
            end

            opened_org_issue.reload
            refute_predicate opened_org_issue, :closed?

            assert_nil opened_org_issue.events.detect { |ev| ev.event == "closed" }
          end
        end

        context "repo scoped" do
          context "can close an issue" do
            test "both the user and app can close" do
              integration = @installation_with_write.integration
              access = integration.grant(@user)

              _, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: @repo.id)
              assert_nil error_response

              append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
              post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

              @opened_issue.reload
              assert_predicate @opened_issue, :closed?

              assert ev = @opened_issue.events.last
              refute ev.async_will_close_subject?.sync

              assert_equal @master.target.oid, ev.commit_id
              assert_equal @user, ev.actor
            end

            test "gracefully handles missing oauth accesses" do
              integration = @installation_with_write.integration
              access = integration.grant(@user)

              _, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: @repo2.id)
              assert_nil error_response

              access.destroy

              append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
              post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

              @opened_issue.reload
              assert_predicate @opened_issue, :closed?
            end
          end

          context "cannot close an issue" do
            test "the user can close but the app cannot close" do
              integration = @installation_with_write.integration
              access = integration.grant(@user)

              _, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: @repo2.id)
              assert_nil error_response

              append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
              post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

              @opened_issue.reload
              refute_predicate @opened_issue, :closed?

              assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
            end

            test "both the user and app cannot close" do
              rando = create(:user)
              repo = create(:repository, owner: @user)

              integration = @installation_with_write.integration
              access = integration.grant(rando)

              _, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: repo.id)
              assert_nil error_response

              append_commit(@master, rando, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
              post_receive(@user, rando, repo, @master, { oauth_access_id: access.id })

              @opened_issue.reload
              refute_predicate @opened_issue, :closed?

              assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
            end

            test "the user can close but an app cannot" do
              integration = @installation_with_write.integration
              access = integration.grant(@user)

              _, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: @repo2.id)
              assert_nil error_response

              append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
              post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

              @opened_issue.reload
              refute_predicate @opened_issue, :closed?

              assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
            end
          end
        end
      end

      context "user programmatic accesses" do
        context "can close an issue" do
          test "user can close and pat can close" do
            access = create(:user_programmatic_access, owner: @user)
            make_programmatic_access_grant(access: access, permissions: { "metadata" => :read, "contents" => :write, "issues" => :write }, repository_selection: :all)

            append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
            post_receive(@user, @user, @repo2, @master, { user_programmatic_access_id: access.id })

            @opened_issue.reload
            assert_predicate @opened_issue, :closed?

            assert ev = @opened_issue.events.last
            refute ev.async_will_close_subject?.sync

            assert_equal @master.target.oid, ev.commit_id
            assert_equal @user, ev.actor
          end
        end

        context "cannot close an issue" do
          test "user can close but PAT cannot" do
            access = create(:user_programmatic_access, owner: @user)
            make_programmatic_access_grant(
              access: access, repository_selection: :subset, repositories: [@repo2],
              permissions: { "metadata" => :read, "contents" => :write, "issues" => :write }
            )

            append_commit(@master, @user, "fix #{@repo.name_with_owner}##{@opened_issue.number}")
            post_receive(@user, @user, @repo2, @master, { user_programmatic_access_id: access.id })

            @opened_issue.reload
            refute_predicate @opened_issue, :closed?

            assert_nil @opened_issue.events.detect { |ev| ev.event == "closed" }
          end
        end
      end
    end

    context "reading issues" do
      context "server-to-server" do
        test "can reference the issue when the installation has access" do
          append_commit(@master, @installation_with_read_bot, "#{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @installation_with_read_bot, @repo2, @master, {
            installation_id: @installation_with_read.id,
            installation_type: @installation_with_read.class.to_s
          })

          @opened_issue.reload
          assert_predicate @opened_issue, :open?

          assert ev = @opened_issue.events.last
          assert_equal "referenced", ev.event

          refute ev.async_will_close_subject?.sync
        end

        test "can reference the issue when the repository is public and the installation has no access" do
          metadata_installation = make_integration_installation(target: @user, permissions: { "metadata" => :read, "contents" => :write })

          bot = metadata_installation.integration.bot
          assert_nil bot.installation

          pub_repo = create(:repository)
          pub_issue = create(:issue, repository: pub_repo, user: pub_repo.owner)

          append_commit(@master, bot, "#{pub_repo.name_with_owner}##{pub_issue.number}")

          post_receive(@user, bot, @repo2, @master, {
            installation_id: metadata_installation.id,
            installation_type: metadata_installation.class.to_s
          })

          @opened_issue.reload
          assert_predicate @opened_issue, :open?

          assert ev = pub_issue.events.last
          assert_equal "referenced", ev.event

          refute ev.async_will_close_subject?.sync
        end

        test "cannot reference the issue when the installation does not have access" do
          append_commit(@master, @repo_2_installation_with_read_bot, "#{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @repo_2_installation_with_read_bot, @repo2, @master, {
            installation_id: @repo_2_installation_with_read.id,
            installation_type: @repo_2_installation_with_read.class.to_s
          })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_predicate @opened_issue.events, :none?
        end
      end

      context "scoped server-to-server" do
        test "can reference the issue when the installation has access" do
          installation = make_scoped_integration_installation(parent: @installation_with_read, repositories: [@repo, @repo2])
          append_commit(@master, @installation_with_read_bot, "#{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @installation_with_read_bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload
          assert_predicate @opened_issue, :open?

          assert ev = @opened_issue.events.last
          assert_equal "referenced", ev.event
        end

        test "cannot reference the issue when the installation does not have access" do
          installation = make_scoped_integration_installation(parent: @installation_with_read, repositories: [@repo2])
          append_commit(@master, @installation_with_read_bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @installation_with_read_bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_predicate @opened_issue.events, :none?
        end

        test "can reference the issue when the repository is public and the installation does not have access" do
          metadata_installation = make_integration_installation(target: @user, permissions: { "metadata" => :read, "contents" => :write })
          installation = make_scoped_integration_installation(parent: metadata_installation, repositories: [@repo2])

          bot = installation.integration.bot
          assert_nil bot.installation

          pub_repo = create(:repository)
          pub_issue = create(:issue, repository: pub_repo, user: pub_repo.owner)

          append_commit(@master, bot, "#{pub_repo.name_with_owner}##{pub_issue.number}")

          post_receive(@user, bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload
          assert_predicate @opened_issue, :open?

          assert ev = pub_issue.events.last
          assert_equal "referenced", ev.event
        end
      end

      context "site scoped server-to-server" do
        test "cannot reference the issue when the installation has access" do
          disable_feature_flag(:disabled_global_apps)

          permissions = { "metadata" => :read, "contents" => :write, "issues" => :read }
          integration = create_unlimited_global_integration(permissions: permissions)

          installation = make_site_scoped_integration_installation(
            integration: integration, target: @user,
            repositories: [@repo, @repo2], permissions: permissions
          )

          bot = integration.bot
          append_commit(@master, bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_predicate @opened_issue.events, :none?
        end

        test "cannot reference the issue when the installation does not have access" do
          disable_feature_flag(:disabled_global_apps)

          permissions = { "metadata" => :read, "contents" => :write, "issues" => :read }
          integration = create_unlimited_global_integration(permissions: permissions)

          installation = make_site_scoped_integration_installation(
            integration: integration, target: @user,
            repositories: [@repo2], permissions: permissions
          )

          bot = integration.bot
          append_commit(@master, bot, "fix #{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_predicate @opened_issue.events, :none?
        end

        test "cannot reference the issue when the repository is public and the installation does not have access" do
          disable_feature_flag(:disabled_global_apps)

          permissions = { "metadata" => :read, "contents" => :write }
          integration = create_unlimited_global_integration(permissions: permissions)

          installation = make_site_scoped_integration_installation(
            integration: integration, target: @user,
            repositories: [@repo, @repo2], permissions: permissions
          )

          pub_repo = create(:repository)
          pub_issue = create(:issue, repository: pub_repo, user: pub_repo.owner)

          bot = integration.bot
          append_commit(@master, bot, "fix #{pub_repo.name_with_owner}##{pub_issue.number}")

          post_receive(@user, bot, @repo2, @master, {
            installation_id: installation.id,
            installation_type: installation.class.to_s
          })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_predicate @opened_issue.events, :none?
        end
      end

      context "user-to-server" do
        test "can reference the issue when the user and installation have access" do
          access = @installation_with_read.integration.grant(@user)
          append_commit(@master, @installation_with_read_bot, "#{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

          @opened_issue.reload
          assert_predicate @opened_issue, :open?

          assert ev = @opened_issue.events.last
          assert_equal "referenced", ev.event
        end

        test "cannot reference the issue when the user has access and the installation does not" do
          integration = create(:integration)
          access = integration.grant(@user)

          append_commit(@master, @user, "#{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_empty @opened_issue.events
        end

        test "cannot reference the issue when the user does not have access and the installation does" do
          rando = create(:user)
          access = @installation_with_read.integration.grant(rando)

          append_commit(@master, rando, "#{@repo.name_with_owner}##{@opened_issue.number}")

          post_receive(@user, rando, @repo2, @master, { oauth_access_id: access.id })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_empty @opened_issue.events
        end

        test "can reference the issue when repository is public and both the user and installation do not have direct access" do
          rando = create(:user)
          access = create(:integration).grant(rando)

          randos_repo = create(:repository, owner: rando)

          pub_repo = create(:repository)
          pub_issue = create(:issue, repository: pub_repo, user: pub_repo.owner)

          append_commit(@master, rando, "#{pub_repo.name_with_owner}##{pub_issue.number}")
          post_receive(rando, rando, randos_repo, @master, { oauth_access_id: access.id })

          assert ev = pub_issue.events.last
          assert_equal "referenced", ev.event
        end

        context "repo-scoped" do
          test "can reference the issue when the user and scoped installation have access" do
            access = @installation_with_read.integration.grant(@user)
            _, error_response = @installation_with_read.integration.grant_repository_scoped_installation_on(access, repository_id: @repo.id)

            append_commit(@master, @installation_with_read_bot, "#{@repo.name_with_owner}##{@opened_issue.number}")

            post_receive(@user, @user, @repo, @master, { oauth_access_id: access.id })

            @opened_issue.reload
            assert_predicate @opened_issue, :open?

            assert ev = @opened_issue.events.last
            assert_equal "referenced", ev.event
          end

          test "cannot reference the issue when the user has access and the installation does not" do
            access = @installation_with_read.integration.grant(@user)
            _, error_response = @installation_with_read.integration.grant_repository_scoped_installation_on(access, repository_id: @repo2.id)

            append_commit(@master, @installation_with_read_bot, "#{@repo.name_with_owner}##{@opened_issue.number}")

            post_receive(@user, @user, @repo2, @master, { oauth_access_id: access.id })

            @opened_issue.reload

            assert_predicate @opened_issue, :open?
            assert_empty @opened_issue.events
          end
        end
      end

      context "user programmatic accesses" do
        test "can reference the issue when the user and pat have access" do
          access = create(:user_programmatic_access, owner: @user)
          make_programmatic_access_grant(access: access, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read }, repository_selection: :all)

          append_commit(@master, @user, "#{@repo.name_with_owner}##{@opened_issue.number}")
          post_receive(@user, @user, @repo2, @master, { user_programmatic_access_id: access.id })

          @opened_issue.reload
          assert_predicate @opened_issue, :open?

          assert ev = @opened_issue.events.last
          assert_equal "referenced", ev.event
        end

        test "cannot reference the issue when the user has access and the pat does not" do
          access = create(:user_programmatic_access, owner: @user)
          make_programmatic_access_grant(
            access: access, repository_selection: :subset, repositories: [@repo2],
            permissions: { "metadata" => :read, "contents" => :write, "issues" => :read }
          )

          append_commit(@master, @user, "#{@repo.name_with_owner}##{@opened_issue.number}")
          post_receive(@user, @user, @repo2, @master, { user_programmatic_access_id: access.id })

          @opened_issue.reload

          assert_predicate @opened_issue, :open?
          assert_empty @opened_issue.events
        end
      end
    end
  end
end
