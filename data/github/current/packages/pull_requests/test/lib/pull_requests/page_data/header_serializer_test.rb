# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    class HeaderSerializerTest < GitHub::TestCase
      fixtures do
        user = create(:user)
        repo = create(:repository, admin: user, from_example: :pull_request_history)
        create(:collaborator, collaborator: user, repository: repo)
        assert repo.member?(user)

        @pull =
          create(:pull_request,
            base_ref: repo.default_branch,
            base_repository: repo,
            base_user: user,
            head_ref_name: "topic",
            head_repository: repo,
            head_user: user,
            repository: repo,
            user: user,
          )

        @base_repository_default_branch = repo.default_branch
        @checks_count = @pull.latest_check_runs_count
        @commit_count = @pull.historical_comparison.commits.size
        @files_changed_count = @pull.historical_comparison.diffs.changed_files
        @head_repository_owner = repo.owner
        @is_in_advisory_repo = @pull.in_advisory_workspace?
        @merged_by = @pull.merged_by&.display_login
        @merged_time = @pull.merged_at&.iso8601&.to_s

        expected_serialized_pr_data = PullRequests::PageData::HeaderSerializer::PullRequestData.new(
          author: user.display_login,
          baseBranch: @pull.display_base_ref_name,
          commitsCount: @commit_count,
          headBranch: @pull.display_head_ref_name,
          headRepositoryOwnerLogin: @head_repository_owner.display_login,
          headRepositoryName: repo.name,
          isInAdvisoryRepo: false,
          number: @pull.number,
          state: @pull.state.to_s,
          title: @pull.title,
          titleHtml: @pull.title_html,
          linesAdded: 1,
          linesDeleted: 0,
          linesChanged: 1,
        )

        expected_serialized_repository_data = PullRequests::PageData::HeaderSerializer::BaseRepositoryData.new(
          codespacesEnabled: true,
          copilotEnabled: false,
          editorEnabled: false,
          defaultBranch: @base_repository_default_branch,
          id: repo.id,
          isEnterprise: false,
          name: repo.name,
          ownerLogin: @head_repository_owner.display_login,
        )

        @base_url = @pull.url(include_host: false)
        expected_serialized_url_data = PullRequests::PageData::HeaderSerializer::UrlsData.new(
          checks: "#{@base_url}/checks",
          commits: "#{@base_url}/commits",
          conversation: "#{@base_url}",
          files: "#{@base_url}/files"
        )

        expected_serialized_user_data = PullRequests::PageData::HeaderSerializer::UserData.new(
          canChangeBase: true,
          canEditTitle: true,
        )

        expected_serialized_banners_payload = PullRequests::PageData::BannersDataPayload.build(
          current_user: @pull.user,
          pull_request: @pull,
          repository: @pull.repository
        )

        @expected_header_serializer_data = PullRequests::PageData::HeaderSerializer::HeaderData.new(
          bannersData: expected_serialized_banners_payload,
          pullRequest: expected_serialized_pr_data,
          repository: expected_serialized_repository_data,
          urls: expected_serialized_url_data,
          user: expected_serialized_user_data,
        ).as_json.freeze
      end

      context "serializes as expected" do
        test "serializes the pull request header with Ruby conventions using to_hash" do
          author_display_login = @pull.user.display_login
          base_repository = @pull.base_repository
          head_repository = @pull.head_repository
          pull_request_display_state = @pull.state.to_s
          banners_data = PullRequests::PageData::BannersDataPayload.build(
            current_user: @pull.user,
            pull_request: @pull,
            repository: @pull.repository
          )

          assert_no_queries do
            actual_serialized_data = PullRequests::PageData::HeaderSerializer.new(
              author_display_login:,
              banners_data: banners_data,
              base_repository:,
              base_repository_default_branch: @base_repository_default_branch,
              base_url: @base_url,
              codespaces_enabled: true,
              commit_count: @commit_count,
              copilot_enabled: false,
              current_user_can_change_base: true,
              current_user_can_edit_title: true,
              editor_enabled: false,
              head_owner: @head_repository_owner,
              head_repository:,
              is_enterprise: false,
              is_in_advisory_repo: @is_in_advisory_repo,
              lines_added: 1,
              lines_changed: 1,
              lines_deleted: 0,
              merged_by: @merged_by,
              merged_time: @merged_time,
              pull_request: @pull,
              pull_request_display_state:,
            ).to_hash

            assert_equal @expected_header_serializer_data, actual_serialized_data
          end
        end
      end
    end
  end
end
