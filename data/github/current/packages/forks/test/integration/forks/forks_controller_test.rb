# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::ForksControllerHttpTest < GitHub::IntegrationTestCase

  include Forks::FixtureHelpers

  FORK_DETAIL_SELECTOR = "div.unstyled-fork-detail"
  PAGE_NUMBER_SELECTOR = "div.pagination a"
  SAVE_BUTTON_SELECTOR = "button[name='save-default-options']"

  fixtures do
    @user = create(:user, login: "testuser")
    @root_repo = create(:repository, owner: @user, from_example: :forkable)
    @forks = [
      create_fork(@root_repo, stargazers: 25, open_issues: 1),  # inactive
      create_fork(@root_repo, open_issues: 2, pushed_at: Time.now + 1.hour),
      create_fork(@root_repo, stargazers: 10, with_pull_request: true, pushed_at: Time.now + 30.minutes)
    ]
  end

  def render_forks(options = {})
    @html = nil
    query = options.to_query

    as @user
    get "/#{repo_forks_path}?#{query}"
  end

  def repo_forks_path
    "/#{@root_repo.name_with_display_owner}/forks"
  end

  test "it renders the default results " do
    render_forks
    assert_rendered_order [@forks.last, @forks.second]
    assert_test_selector "fork-detail", 2
    assert_select PAGE_NUMBER_SELECTOR, 0
  end

  def assert_rendered_detail_counts(detail_selector, expected_counts)
    counts = rendered_html.css("[data-test-selector='fork-detail-#{detail_selector}']")
      .map { |e| e.text.to_i }
    assert_equal expected_counts, counts
  end

  def assert_rendered_order(expected_forks_order)
    rendered_order = rendered_html.css("[data-test-selector='fork-detail-heading']")
      .map { |e| e.text.strip.gsub(/\s/, "") }
    expected_order = expected_forks_order.map { |f| f.name_with_display_owner }
    assert_equal expected_order, rendered_order
  end

  def rendered_html
    @html ||= Nokogiri::HTML(response.body)
  end

  def assert_save_button_disabled
    assert_select "#{SAVE_BUTTON_SELECTOR}[disabled='disabled']"
  end

  def assert_save_button_enabled
    assert_select "button:not([disabled])[name='save-default-options']"
  end

  # While other test ensure that what the forks helper returns is correct,
  # these tests explicitly check that what is rendered in the view matches
  # the expected state of the collection.
  context "#index" do
    context "it renders the collection" do
      test "it sorts by pull request" do
        render_forks(sort_by: :open_pull_request_counts, include: "active,inactive")
        assert_rendered_order([@forks.last, @forks.first, @forks.second])
        assert_rendered_detail_counts("open-pull-requests-count", [1, 0, 0])
        assert_rendered_detail_counts("open-issues-count", [0, 1, 2])
        assert_rendered_detail_counts("stargazers-count", [10, 25, 0])
      end

      test "it sorts by open issues" do
        render_forks(sort_by: :open_issue_counts, include: "active,inactive")
        assert_rendered_order([@forks.second, @forks.first, @forks.last])
        assert_rendered_detail_counts("open-issues-count", [2, 1, 0])
        assert_rendered_detail_counts("open-pull-requests-count", [0, 0, 1])
        assert_rendered_detail_counts("stargazers-count", [0, 25, 10])
      end

      test "it sorts by stars" do
        render_forks(sort_by: :stargazer_counts, include: "active,inactive")
        assert_rendered_order([@forks.first, @forks.last, @forks.second])
        assert_rendered_detail_counts("stargazers-count", [25, 10, 0])
        assert_rendered_detail_counts("open-pull-requests-count", [0, 1, 0])
        assert_rendered_detail_counts("open-issues-count", [1, 0, 2])
      end

      test "it sorts by most recently pushed" do
        render_forks(sort_by: :last_updated, include: "active,inactive")
        # We don't validate the displayed values here because Primer::Beta::RelativeTime requires
        # javascript to run, so the values being tested will not reflect
        # the rendered value that users will see. (In other words, there's not really a point.)
        assert_rendered_order([@forks.second, @forks.last, @forks.first])
      end

      if !TestEnv.test_with_all_emus?
        test "it includes forks of forks" do
          network_fork = create_fork(@forks.first, pushed_at: Time.now + 1.hour, forker: "network-forker")

          render_forks(include: "active,network")
          assert_rendered_order([@forks.third, @forks.second, network_fork])
        end
      end
    end

    context "when the repo does not exist" do
      test "it returns a 404" do
        get "/#{@user.display_login}/this-repo-does-not-exist/forks"
        assert_response_not_found
      end
    end

    context "when there are no results" do
      context "when the user has an impossible query" do
        test "it renders with no forks found" do
          render_forks(include: "starred")  # Neither inactive nor active is supplied; starred is irrelevant
          refute_test_selector "fork-detail"
          assert_test_selector "empty-forks", text: /No forked repositories found/
        end
      end

      context "when the user's query is too strict" do
        test "it renders with no forks found" do
          @forks.first.destroy # Only destroy the inactive fork, then query for it
          render_forks(include: "inactive")
          assert_test_selector "empty-forks", text: /No forked repositories found/
        end
      end

      context "when the repository has no forks" do
        test "it renders with no forks ever" do
          @root_repo.forks.destroy_all
          render_forks(include: "active,inactive")
          assert_test_selector "empty-forks", text: /No one has forked this repository/
        end
      end

      if GitHub.spamminess_check_enabled?
        context "when only spammy forks are included in the results" do
          test "it renders with no forks found" do
            # Here, the repo has an inactive fork that is not spammy, so
            # the messaging should reflect that a user can update their query
            @root_repo.forks.destroy_all
            spammer = create(:user, spammy: false)
            forker = create(:user)
            spammy_fork = create(:fork_repository, fork_repo: @root_repo, forker: spammer, pushed_at: Time.now + 1.hour)
            perform_enqueued_jobs(only: UpdateTableUserHiddenJob) { spammer.mark_as_spammy }
            inactive_fork = @root_repo.fork(forker:)
            resp = render_forks(include: "active")
            assert_test_selector "empty-forks", text: /No forked repositories found/
          end
        end

        context "when the repository only has spammy forks" do
          test "it renders with no forks ever" do
            # Here, there are no reachable forks that are
            # not spammy, so we should tell the user it has no forks;
            # there is no reason for them to amend their search.
            @root_repo.forks.destroy_all
            spammer = create(:user, spammy: true)
            spammy_fork = @root_repo.fork(forker: spammer, pushed_at: Time.now + 1.hour)
            render_forks(include: "active,inactive")
            assert_test_selector "empty-forks", text: /No one has forked this repository/
          end
        end

        context "when the user has default settings saved" do
          if GitHub.flipper[:forks_view_user_default_options].enabled?
            if TestEnv.test_with_all_emus?
              test "forks are rendered with user's saved settings" do
                network_fork = create_fork(@forks.first, pushed_at: Time.now + 1.hour, forker: "network-forker")

                as @user
                render_forks
                assert_rendered_order [@forks.last, @forks.second]

                settings = T.cast(UserSettings.create_or_find_by(user_id: @user.id), T.untyped)
                settings.set!(:forks_view_default_options, save_options_payload(include: "active,network").to_json)

                render_forks

                assert_rendered_order [@forks.third, @forks.second, network_fork]
                assert_save_button_disabled
              end
            end

            test "save button is enabled if rendered options do not match user options" do
              as @user
              render_forks
              assert_rendered_order [@forks.last, @forks.second]

              settings = T.cast(UserSettings.create_or_find_by(user_id: @user.id), T.untyped)
              settings.set!(:forks_view_default_options, save_options_payload(include: "active,network").to_json)

              render_forks(include: "archived") # Providing this param means the params won't match the user defaults
              # And because they don't match, the user will have the option to save the new set as their defaults
              assert_save_button_enabled
            end
          else
            test "user default settings are ignored" do
              settings = T.cast(UserSettings.create_or_find_by(user_id: @user.id), T.untyped)
              settings.set!(:forks_view_default_options, save_options_payload(include: "active,network").to_json)

              render_forks
              assert_rendered_order [@forks.last, @forks.second]
            end
          end
        end
      end

      if GitHub.flipper[:forks_view_unbound_period].enabled?
        context "when the All time option is selected" do
          test "All forks are rendered" do
            throwback_fork = create_fork(@root_repo, created_at: Time.now - 6.years, pushed_at: Time.now - 6.years + 1.day)
            render_forks(period: "")
            assert_rendered_order [@forks.last, @forks.second, throwback_fork]
          end
        end
      else
        context "When no period is selected" do
          test "It renders the default period" do
            throwback_fork = create_fork(@root_repo, created_at: Time.now - 6.years, pushed_at: Time.now - 6.years + 1.day)
            render_forks(period: "")
            assert_rendered_order [@forks.last, @forks.second]
          end
        end
      end
    end
  end

  def save_options_payload(**overrides)
    {
      sort_by: "stargazer_counts",
      include: "active,inactive,archived",
      period: "5y",
    }.merge(overrides)
  end
end
