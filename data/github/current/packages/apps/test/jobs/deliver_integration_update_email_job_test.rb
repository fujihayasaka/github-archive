# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeliverIntegrationUpdateEmailJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @admin             = create(:user, login: "org-admin")
    @another_org_admin = create(:user, login: "org-admin-2")
    @org               = create(:organization, admins: [@admin, @another_org_admin])

    @public_org_repo           = create(:repository, :minimal, owner: @org)
    @private_org_repo          = create(:private_repository, :minimal, owner: @org)
    @another_private_org_repo  = create(:private_repository, :minimal, owner: @org)

    @non_org_owner_repo_admin         = create(:user, login: "noora")
    @another_non_org_owner_repo_admin = create(:user, login: "noora-2")

    @public_org_repo.add_member(@non_org_owner_repo_admin, action: :admin)

    @private_org_repo.add_member(@non_org_owner_repo_admin, action: :admin)
    @private_org_repo.add_member(@another_non_org_owner_repo_admin, action: :admin)

    @another_private_org_repo.add_member(@non_org_owner_repo_admin, action: :admin)

    @user_installation       = make_integration_installation(target: @admin, permissions: { "metadata" => :read })
    @org_target_installation = make_integration_installation(target: @org,   permissions: { "metadata" => :read })
    @org_subset_installation = make_integration_installation(repositories: [@public_org_repo, @private_org_repo], permissions: { "metadata" => :read })
  end

  setup { ActionMailer::Base.deliveries.clear }

  context ".perform" do

    context "failure" do
      test "retry conditions" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        assert_retry_on_dirty_exit job: DeliverIntegrationUpdateEmailJob, args: [@org_subset_installation.id]
        assert_equal 1, GitHub.dogstats.increments("active_job.retry", tags: [
          "class:deliver_integration_update_email_job",
        ]).length
      end
    end

    context "target type User installation" do
      test "only send an email the User target" do
        DeliverIntegrationUpdateEmailJob.perform_now(@user_installation.id)

        assert_equal 1, ActionMailer::Base.deliveries.size
        mail = ActionMailer::Base.deliveries.first

        assert_equal [@admin.email], mail.to
        assert_equal "[GitHub] #{@user_installation.integration.name} is requesting updated permissions", mail.subject
        assert_match "/settings/installations/#{@user_installation.id}/permissions/update", mail.text_part.body.to_s
        assert_match "/settings/installations/#{@user_installation.id}/permissions/update", mail.html_part.body.to_s
      end
    end

    context "target type Organization installation" do
      context "installation on all repositories" do
        test "sends emails to the organization admins" do
          DeliverIntegrationUpdateEmailJob.perform_now(@org_target_installation.id)

          assert_equal 2, ActionMailer::Base.deliveries.size
          emails = ActionMailer::Base.deliveries

          receipients = emails.map(&:to).flatten
          assert_includes receipients, @admin.email
          assert_includes receipients, @another_org_admin.email

          emails.each do |mail|
            assert_equal "[GitHub] #{@org_target_installation.integration.name} is requesting updated permissions", mail.subject
            assert_match "/organizations/#{@org.display_login}/settings/installations/#{@org_target_installation.id}/permissions/update", mail.text_part.body.to_s
            assert_match "/organizations/#{@org.display_login}/settings/installations/#{@org_target_installation.id}/permissions/update", mail.html_part.body.to_s
          end
        end

        test "does not send emails to repo admins even if there are repo admins who can manage all of the repos" do
          @another_private_org_repo.add_member(@non_org_owner_repo_admin, action: :admin)
          assert @org_target_installation.repositories.all? { |repo| repo.adminable_by?(@non_org_owner_repo_admin) }

          DeliverIntegrationUpdateEmailJob.perform_now(@org_target_installation.id)

          assert_equal 2, ActionMailer::Base.deliveries.size
          emails = ActionMailer::Base.deliveries

          receipients = emails.map(&:to).flatten
          refute_includes receipients, @non_org_owner_repo_admin.email
        end
      end

      context "installation on a subset of repositories with repository permissions" do
        test "send emails to the organization admins" do
          DeliverIntegrationUpdateEmailJob.perform_now(@org_subset_installation.id)

          assert_equal 3, ActionMailer::Base.deliveries.size
          emails = ActionMailer::Base.deliveries

          receipients = emails.map(&:to).flatten
          assert_includes receipients, @admin.email
          assert_includes receipients, @another_org_admin.email

          # Grab only the mail for the org admins
          emails = emails.select { |mail| ([@admin.email, @another_org_admin.email] & mail.to).any? }

          emails.each do |mail|
            assert_equal "[GitHub] #{@org_subset_installation.integration.name} is requesting updated permissions", mail.subject
            assert_match "/organizations/#{@org.display_login}/settings/installations/#{@org_subset_installation.id}/permissions/update", mail.text_part.body.to_s
            assert_match "/organizations/#{@org.display_login}/settings/installations/#{@org_subset_installation.id}/permissions/update", mail.html_part.body.to_s
          end
        end

        test "sends emails to the repo admins who can manage the entire subset" do
          assert @org_subset_installation.repositories.all? { |repo| repo.adminable_by?(@non_org_owner_repo_admin) }

          DeliverIntegrationUpdateEmailJob.perform_now(@org_subset_installation.id)

          assert_equal 3, ActionMailer::Base.deliveries.size
          emails = ActionMailer::Base.deliveries

          receipients = emails.map(&:to).flatten
          assert_includes receipients, @non_org_owner_repo_admin.email

          # Grab only the mail for the repo admins
          emails = emails.select { |mail| ([@non_org_owner_repo_admin.email] & mail.to).any? }

          path_prefix = GitHub.enterprise? ? "github-apps" : "apps"

          integration_path = if GitHub.flipper[:owner_scoped_github_apps].enabled?
            "#{@org_subset_installation.integration.owner}/#{@org_subset_installation.integration.slug}"
          else
            "#{@org_subset_installation.integration.slug}"
          end

          path = "/#{path_prefix}/#{integration_path}/installations/#{@org_subset_installation.id}/permissions"
          emails.each do |mail|
            assert_equal "[GitHub] #{@org_subset_installation.integration.name} is requesting updated permissions", mail.subject
            assert_match path, mail.text_part.body.to_s
            assert_match path, mail.html_part.body.to_s
          end
        end

        test "does not end emails to the repo admins who cannot manage the entire subset" do
          refute @org_subset_installation.repositories.all? { |repo| repo.adminable_by?(@another_non_org_owner_repo_admin) }

          DeliverIntegrationUpdateEmailJob.perform_now(@org_subset_installation.id)

          assert_equal 3, ActionMailer::Base.deliveries.size
          emails = ActionMailer::Base.deliveries

          receipients = emails.map(&:to).flatten
          refute_includes receipients, @another_non_org_owner_repo_admin.email
        end

        test "does not send emails to repo admins who can't update the installation" do
          version = IntegrationVersion.create(integration: @org_subset_installation.integration, default_permissions: { "metadata" => :read, "administration" => :write })
          permissions_result = IntegrationInstallation::Permissions.check(
            installation: @org_subset_installation, actor: @non_org_owner_repo_admin, action: :update_permissions
          )

          refute_predicate permissions_result, :permitted?

          DeliverIntegrationUpdateEmailJob.perform_now(@org_subset_installation.id, integration_version_id: version.id)

          assert_equal 2, ActionMailer::Base.deliveries.size
          emails = ActionMailer::Base.deliveries

          receipients = emails.map(&:to).flatten
          refute_includes receipients, @non_org_owner_repo_admin.email
        end

        context "with organization permissions" do
          test "does not send emails to the repo admins who can manage the entire subset" do
            assert @org_subset_installation.repositories.all? { |repo| repo.adminable_by?(@non_org_owner_repo_admin) }

            create(:integration_version, integration: @org_subset_installation.integration, default_permissions: { "metadata" => :read, "members" => :read })

            DeliverIntegrationUpdateEmailJob.perform_now(@org_subset_installation.id)

            assert_equal 2, ActionMailer::Base.deliveries.size
            emails = ActionMailer::Base.deliveries

            receipients = emails.map(&:to).flatten
            refute_includes receipients, @non_org_owner_repo_admin.email
          end
        end
      end
    end
  end
end
