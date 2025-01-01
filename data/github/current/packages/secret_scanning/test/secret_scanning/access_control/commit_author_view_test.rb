# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::AccessControl
  class CommitAuthorViewTest < GitHub::TestCase
    include FineGrainedPermissionsTestHelper

    fixtures do
      @owner = create(:user)
      @direct_collaborator = create(:user)
      @external_collaborator = create(:user)
      @rando = create(:user)

      # create user repo with direct collaborator
      @user_repo = create(:public_repository, owner: @owner)
      @user_repo.add_member(@direct_collaborator)

      @org = create(:business_plus_org, admin: @owner)
      @org_repo = create(:public_repository, owner: @org)
      @org_repo.add_member(@rando)
      grant_custom_role(user: @external_collaborator, target: @org_repo, fgps: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts])
    end

    setup do
    end

    context "#has_access_to_repository?" do
      test "manages access for user owned public repositories" do
        subj = CommitAuthorView.new(@user_repo)
        assert subj.has_access_to_repository?(@owner)
        assert subj.has_access_to_repository?(@direct_collaborator)

        refute subj.has_access_to_repository?(@rando)
        refute subj.has_access_to_repository?(@external_collaborator)
      end

      test "manages access for user org public repositories" do
        subj = CommitAuthorView.new(@org_repo)

        # owner is always allowed
        assert subj.has_access_to_repository?(@owner)

        # rando was explicitly added as a member
        assert subj.has_access_to_repository?(@rando)
        assert subj.has_access_to_repository?(@external_collaborator)

        refute subj.has_access_to_repository?(@direct_collaborator)
      end
    end
  end
end
