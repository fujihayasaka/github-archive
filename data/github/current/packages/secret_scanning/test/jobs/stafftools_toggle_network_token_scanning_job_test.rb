# typed: true
# frozen_string_literal: true

require "test_helper"
require "github-launch"

module SecretScanning::Jobs
  class StafftoolsToggleNetworkTokenScanningJobTest < GitHub::TestCase
    include NewsiesHelper
    include StafftoolsHelper

    fixtures do
      @staffer  = create :staff_admin_user
      @user     = create(:user)
      @user2    = create :paid_user
      @repo     = create(:repository)
      @repo2    = create(:repository)
      @fork = create(:fork_repository, forker: @user, fork_repo: @repo)

      @repo.create_page

      @repo.initialize_wiki(@repo.owner)
      example_repo :wiki, @repo.unsullied_wiki

      @user_repo = create :repository, owner: @user
      @org = create :business_plus_organization
      @org_repo  = create :repository, owner: @org
      @org_repo2 = create(:private_repository, owner: @org)
      @org_admin = @org.members.first

      PrereleaseProgramMember.create(member: @org_repo.owner, actor: @org_admin)

      @private_repo = create :private_repository, owner: @user2
      @private_repo.add_member @user
      @private_fork = create(:fork_repository, forker: @user, fork_repo: @private_repo)
      @staffer.stafftools_roles << StafftoolsRole.new(name: "super-admin")
    end

    setup do
      ActionMailer::Base.deliveries.clear
      enable_cache_storage
      reset_cache
    end

    context "#toggle_network_token_scanning", skip_enterprise: true do
      test "disable secret scanning on network" do
        events = subscribe "repository_secret_scanning.disable"

        StafftoolsToggleNetworkTokenScanningJob.perform_now(@repo.id, @repo.owner.id, nil)

        assert event = events.pop, "expected a disable event to be triggered"
        assert_equal true, event.payload[:use_staff_key]
        assert_equal true, event.payload[:network?]
        assert_equal @fork.id, event.payload[:repo_id]
      end

      test "enable secret scanning on network" do
        events = subscribe "repository_secret_scanning.enable"
        SecretScanning::Features::Repo::TokenScanning.new(@fork).disable(actor: @fork.owner)

        StafftoolsToggleNetworkTokenScanningJob.perform_now(@repo.id, @repo.owner.id, 1)

        assert event = events.pop, "expected an enable event to be triggered"
        assert_equal true, event.payload[:use_staff_key]
        assert_equal true, event.payload[:network?]
        assert_equal @fork.id, event.payload[:repo_id]
      end
    end

  end
end
