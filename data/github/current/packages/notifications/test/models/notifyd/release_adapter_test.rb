# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class ReleaseAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @owner = create(:user, login: "owner")
      @author = create(:user, login: "author")
      @repo = create(:repository, owner: @owner, name: "repo", from_example: :simple)
      @release = create(:release, tag_name: "v1", name: "Version One!", author: @owner, repository: @repo, body: "<p>Hello world</p>")
    end

    test "matches for releases" do
      assert adapter(@release).matches?
    end

    test "does not match if repository is missing" do
      @release.repository.delete
      @release.reload

      refute adapter(@release).matches?
    end

    test "returns notify feature flag value" do
      assert_equal GitHub.flipper[:notifyd_release_notify], adapter(@release).notify_feature_flag
    end

    test "returns notification_id for releases" do
      repository_name = @release.repository.name_with_owner

      assert_equal adapter(@release).notification_id,
        "/#{repository_name}/releases/tag/#{@release.tag_name}"
    end

    test "implements repository_id" do
      assert_equal adapter(@release).repository_id, @release.repository_id
    end

    test "implements owner_id" do
      refute_nil adapter(@release).owner_id
      assert_equal adapter(@release).owner_id, @release.repository.owner.id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org, from_example: :simple)
        actor = create(:user)
        org.add_admin(actor)
        release = create(:release, repository: repo, author: actor)

        assert_equal adapter(release).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@release).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@release).authzd_attributes, @release.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@release).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org, from_example: :simple)
        actor = create(:user)
        org.add_admin(actor)
        release = create(:release, repository: repo, author: actor)

        assert_equal adapter(release).saml_enforcement, { organization_id: org.id }
      end
    end

    test "mobile_layout" do
      refute_nil adapter(@release, { actor_id: @release.user.id }).mobile_layout
    end

    test "email_layout" do
      assert_nil adapter(@release, { actor_id: @release.user.id }).email_layout
    end

    private

    def adapter(release, context = {})
      Notifyd::ReleaseAdapter.new(release, context)
    end
  end
end
