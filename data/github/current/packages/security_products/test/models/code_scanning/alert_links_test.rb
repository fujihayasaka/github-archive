# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class AlertLinksTest < GitHub::TestCase
    include ResiliencyHelpers

    fixtures do
      @org = create(:organization)

      @repo1 = create(:repository, owner: @org, from_example: :pull_request_source)
      @repo2 = create(:repository, owner: @org, from_example: :pull_request_source)

      @repo1.heads.create("feature1", @repo1.heads.read("master").target, @org)
      @repo2.heads.create("feature", @repo2.heads.read("master").target, @org)
      @repo2.heads.create("feature1", @repo2.heads.read("master").target, @org)
      @repo2.heads.create("feature2", @repo2.heads.read("master").target, @org)

      @pr1 = create(:pull_request, repository: @repo1, base_repository: @repo1, head_repository: @repo1, head_ref: "master-merged-topic")
      @pr2 = create(:pull_request, repository: @repo2, base_repository: @repo2, head_repository: @repo2, head_ref: "master-merged-topic")
    end

    test "doesn't make a request to turboscan when repos_and_alerts is empty" do
      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .never

      alert_links = AlertLinks.load([])

      refute_nil alert_links
      assert_empty alert_links.get_links(repo_id: @repo1.id, alert_number: 1)
    end

    test "returns empty alert links when unable to contact turboscan" do
      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .once
        .with({ repos_and_alerts: [
          Turboscan::Proto::RepoNumber.new({ number: 14, repository_id: @repo1.id }),
        ] })
        .returns(
          Twirp::ClientResp.new(
            error: Twirp::Error.new(:internal, "some error"),
          )
        )

      alert_links = AlertLinks.load([
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 14)
      ])
      refute_nil alert_links
    end

    test "returns empty pull requests when failing to query pull requests", skip_enterprise: true do
      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .once
        .with({ repos_and_alerts: [
          Turboscan::Proto::RepoNumber.new({ number: 1, repository_id: @repo1.id }),
          Turboscan::Proto::RepoNumber.new({ number: 2, repository_id: @repo2.id }),
        ] })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::GetLinksForAlertsResponse.new({
              links: [
                Turboscan::Proto::AlertLink.new({ alert_number: 1, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo2.id, ref_name_bytes: "refs/heads/feature" }),
              ],
            })
          )
        )

      alert_links = prevent_connections_to(ApplicationRecord::IssuesPullRequests) do
        AlertLinks.load([
          CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 1),
          CodeScanning::RepoAlertTuple.new(repository_id: @repo2.id, alert_number: 2),
        ])
      end

      assert_equal @repo1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.repository_id
      assert_equal 1, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.alert_number
      assert_nil alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.pull_request
      assert_nil alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.branch

      assert_equal @repo2.id, alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.repository_id
      assert_equal 2, alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.alert_number
      assert_nil alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.pull_request
      assert_equal "feature", alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.name
      assert_equal "feature", alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.name_for_display
      refute_nil alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.last_modified_at
    end

    test "converts link details to internal AlertLink class" do
      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .once
        .with({ repos_and_alerts: [
          Turboscan::Proto::RepoNumber.new({ number: 1, repository_id: @repo1.id }),
          Turboscan::Proto::RepoNumber.new({ number: 2, repository_id: @repo2.id }),
        ] })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::GetLinksForAlertsResponse.new({
              links: [
                Turboscan::Proto::AlertLink.new({ alert_number: 1, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo2.id, ref_name_bytes: "refs/heads/feature" }),
              ],
            })
          )
        )

      alert_links = AlertLinks.load([
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 1),
        CodeScanning::RepoAlertTuple.new(repository_id: @repo2.id, alert_number: 2),
      ])

      assert_equal @repo1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.repository_id
      assert_equal 1, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.alert_number
      assert_equal @pr1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.pull_request&.id
      assert_nil alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.branch

      assert_equal @repo2.id, alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.repository_id
      assert_equal 2, alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.alert_number
      assert_nil alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.pull_request
      assert_equal "feature", alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.name
      assert_equal "feature", alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.name_for_display
      refute_nil alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.last_modified_at
    end

    test "groups links together by repository and alert number" do
      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .once
        .with({ repos_and_alerts: [
          Turboscan::Proto::RepoNumber.new({ number: 1, repository_id: @repo1.id }),
          Turboscan::Proto::RepoNumber.new({ number: 2, repository_id: @repo1.id }),
          Turboscan::Proto::RepoNumber.new({ number: 3, repository_id: @repo2.id }),
        ] })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::GetLinksForAlertsResponse.new({
              links: [
                Turboscan::Proto::AlertLink.new({ alert_number: 1, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo1.id, ref_name_bytes: "refs/heads/feature1" }),
                Turboscan::Proto::AlertLink.new({ alert_number: 3, repository_id: @repo2.id, pull_request_id: @pr2.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 3, repository_id: @repo2.id, ref_name_bytes: "refs/heads/feature2" }),
              ],
            })
          )
        )

      alert_links = AlertLinks.load([
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 1),
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 2),
        CodeScanning::RepoAlertTuple.new(repository_id: @repo2.id, alert_number: 3),
      ])

      assert_equal 1, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).size
      assert_equal 2, alert_links.get_links(repo_id: @repo1.id, alert_number: 2).size
      assert_equal 2, alert_links.get_links(repo_id: @repo2.id, alert_number: 3).size
    end

    test "deduplicates links by ref name and pull request" do
      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .once
        .with({ repos_and_alerts: [
          Turboscan::Proto::RepoNumber.new({ number: 1, repository_id: @repo1.id }),
          Turboscan::Proto::RepoNumber.new({ number: 2, repository_id: @repo2.id }),
        ] })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::GetLinksForAlertsResponse.new({
              links: [
                Turboscan::Proto::AlertLink.new({ alert_number: 1, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 1, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo2.id, ref_name_bytes: "refs/heads/feature1" }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo2.id, ref_name_bytes: "refs/heads/feature1" }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo2.id, ref_name_bytes: "refs/heads/feature2" }),
              ],
            })
          )
        )

      alert_links = AlertLinks.load([
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 1),
        CodeScanning::RepoAlertTuple.new(repository_id: @repo2.id, alert_number: 2),
      ])

      assert_equal 1, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).size
      assert_equal @pr1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.pull_request&.id

      assert_equal 2, alert_links.get_links(repo_id: @repo2.id, alert_number: 2).size
      assert_equal "feature1", alert_links.get_links(repo_id: @repo2.id, alert_number: 2).first&.branch&.name
      assert_equal "feature2", alert_links.get_links(repo_id: @repo2.id, alert_number: 2).second&.branch&.name
    end

    test "excludes spammy PRs", skip_enterprise: true, skip_in_multitenant_mode: true do
      spammy_user = create(:user, spammy: true)
      spammy_pr = create(:pull_request, repository: @repo1, base_repository: @repo1, head_repository: @repo1, head_ref: "update-file-1", user: spammy_user, user_hidden: true)

      GitHub::Turboscan
        .expects(:get_links_for_alerts)
        .once
        .with({ repos_and_alerts: [
          Turboscan::Proto::RepoNumber.new({ number: 1, repository_id: @repo1.id }),
          Turboscan::Proto::RepoNumber.new({ number: 2, repository_id: @repo1.id }),
        ] })
        .returns(
          Twirp::ClientResp.new(
            data: Turboscan::Proto::GetLinksForAlertsResponse.new({
              links: [
                Turboscan::Proto::AlertLink.new({ alert_number: 1, repository_id: @repo1.id, pull_request_id: @pr1.id }),
                Turboscan::Proto::AlertLink.new({ alert_number: 2, repository_id: @repo1.id, pull_request_id: spammy_pr.id }),
              ],
            })
          )
        )

      alert_links = AlertLinks.load([
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 1),
        CodeScanning::RepoAlertTuple.new(repository_id: @repo1.id, alert_number: 2),
      ])

      assert_equal @repo1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.repository_id
      assert_equal 1, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.alert_number
      assert_equal @pr1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.pull_request&.id
      assert_nil alert_links.get_links(repo_id: @repo1.id, alert_number: 1).first&.branch

      assert_equal @repo1.id, alert_links.get_links(repo_id: @repo1.id, alert_number: 2).first&.repository_id
      assert_equal 2, alert_links.get_links(repo_id: @repo1.id, alert_number: 2).first&.alert_number
      assert_nil alert_links.get_links(repo_id: @repo1.id, alert_number: 2).first&.pull_request
      assert_nil alert_links.get_links(repo_id: @repo1.id, alert_number: 2).first&.branch
    end
  end
end
