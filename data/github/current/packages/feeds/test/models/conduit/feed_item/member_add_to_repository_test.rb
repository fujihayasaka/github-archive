# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::MemberAddToRepositoryTest < GitHub::TestCase
    fixtures do
      @repository = create(:repository)
      @member = create(:user)
    end

    setup do
      @repository_membership = Conduit::RepositoryMembership.new(
        repository: @repository,
        member: @member,
      )
      @twirp_item = build(
        :twirp_conduit_repository_feed_item,
        repository: @repository,
        action: Conduit::TwirpHelper.updated_action
      )
      @feed_item = Conduit::FeedItem::MemberAddToRepository.new(
        @twirp_item,
        actor: @repository.owner,
        subject: @repository_membership
      )
    end

    context "#repository" do
      test "returns the repository" do
        assert_equal @repository, @feed_item.repository
      end
    end

    context "#member" do
      test "returns the member" do
        assert_equal @member, @feed_item.member
      end
    end

    context "#action_string" do
      test "returns added when not a rollup" do
        assert_equal "added", @feed_item.action_string
      end

      test "returns roll up item count for action string" do
        @feed_item.stubs(:related_items).returns(1..4)

        assert_equal "added 5 members to", @feed_item.action_string
      end
    end

    context "#resource_type" do
      test "returns REPO" do
        assert_equal "REPO", @feed_item.resource_type
      end
    end

    context "#resource_id" do
      test "returns the repository ID" do
        assert_equal @repository.id, @feed_item.resource_id
      end
    end

    context "#subject" do
      test "returns repository" do
        assert_equal @repository_membership, @feed_item.subject
      end
    end

    context "subject_id" do
      test "returns nil since the subject is RepositoryMember" do
        assert_nil @feed_item.subject_id
      end
    end

    context "#analytics_card_type" do
      test "is correct" do
        assert_equal "MEMBER_ADD_TO_REPO", @feed_item.analytics_card_type
      end
    end

    context "description" do
      test "is correct" do
        actor = @feed_item.actor
        assert_equal \
         "#{actor.display_login} added #{@member.display_login} to #{@repository.name_with_display_owner}",
          @feed_item.description
      end
    end

    context "#payload" do
      test "it returns member information" do
        assert_equal @member.id, @feed_item.payload[:member][:id]
      end
    end
  end
end
