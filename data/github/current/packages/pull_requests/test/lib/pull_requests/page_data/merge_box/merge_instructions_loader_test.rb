# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module MergeBox
      class MergeInstructionsLoaderTest < GitHub::TestCase
        include GitHub::QueryAssertionTestHelpers

        fixtures do
          @owner = create(:user, login: "wiseguy")
          @forker = create(:user, login: "sweetsue")
          @org = create :organization, plan: "bronze", admin: @owner

          @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
          create(:collaborator, collaborator: @forker, repository: @source)

          @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

          @pull =
            create(:pull_request,
              repository: @source,
              base_repository: @source,
              base_user: @source.owner,
              base_ref: "master",
              head_repository: @fork,
              head_user: @fork.owner,
              head_ref: "topic",
              user: @forker
            )
        end

        test "returns basic data" do
          data = assert_query_counts(8) do
            PullRequests::PageData::MergeBox::MergeInstructionsLoader.load(viewer: @owner, pull_request: @pull)
          end

          assert_equal data.pull_request, @pull
          assert_equal data.comparison, @pull.comparison
          assert_equal data.viewer, @owner
          assert_equal data.push_protocols.as_json(only: [:is_default, :url, :sticky_url, :available, :to_sym]), PullRequests::PageData::MergeBox::ProtocolSelector.new(repository: @source, user: @owner).protocols.as_json(only: [:is_default, :url, :sticky_url, :available, :to_sym])
        end
      end
    end
  end
end
