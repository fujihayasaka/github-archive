# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment do
  include ActiveJob::TestHelper

  subject(:action) { described_class.new(webhook_body: webhook_body, headers: headers) }

  let(:webhook_body) do
    hash = json_fixture("github_webhooks/issue_comment")
    hash.deep_symbolize_keys
  end
  let(:headers) { nil }

  context "for a non-dependabot issue" do
    before do
      webhook_body[:issue][:user][:login] = "greysteil"
    end

    it "no-ops" do
      expect(Dependabot::Logger).not_to receive(:info)
      expect(MetricsClient).not_to receive(:timing).
        with("issue_comment.age_at_reply", anything, anything)
      expect(MetricsClient).not_to receive(:timing).
        with("issue_comment.age_at_receive", anything, anything)
      expect(MetricsClient).not_to receive(:increment)
      perform_enqueued_jobs do
        action.run
      end
    end
  end

  context "for a dependabot issue that a repo isn't in the database for" do
    it "no-ops but logs" do
      expect(Dependabot::Logger).
        to receive(:info).
        with(hash_including(msg: /Ignoring/))
      expect(MetricsClient).not_to receive(:timing).
        with("issue_comment.age_at_reply", anything, anything)
      expect(MetricsClient).not_to receive(:timing).
        with("issue_comment.age_at_receive", anything, anything)
      perform_enqueued_jobs do
        action.run
      end
    end
  end

  context "for a dependabot issue that a PR isn't in the database for" do
    let(:closed_at) { 2.days.ago.utc.floor(0) }
    let(:created_at) { Time.zone.parse(webhook_body[:issue][:created_at]).utc }

    before do
      webhook_body[:comment][:body] = "@dependabot rebase"
      webhook_body[:issue][:closed_at] = closed_at.iso8601
    end

    it "responds with a comment on the PR" do
      repo = create(:repo, :bump_test)

      expect { action.run }.
        to enqueue_job(CreateMissingDependabotPrCommentJob).
        with(
          repo: repo, github_number: 122, comment_url: webhook_body.dig(:comment, :html_url),
          pr_closed_at: closed_at, pr_created_at: created_at
        )
    end
  end

  context "for a dependabot pull request" do
    let!(:pull_request) do
      FactoryBot.create(:pull_request, :bump_test, github_number: 122)
    end
    let(:repo) { pull_request.repo }
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }

    let(:pr_comments_url) do
      repo_url + "issues/#{pull_request.github_number}/comments"
    end

    describe "given a 'random' webhook" do
      before { webhook_body[:action] = "random" }

      it "logs and ignores the webhook" do
        expect(Dependabot::Logger).
          to receive(:info).
          with(hash_including(msg: /Ignoring/))
        expect(MetricsClient).not_to receive(:timing).
          with("issue_comment.age_at_reply", anything, anything)
        expect(MetricsClient).not_to receive(:timing).
          with("issue_comment.age_at_receive", anything, anything)
        perform_enqueued_jobs do
          action.run
        end
      end
    end

    describe "given a 'created' webhook" do
      context "asking for a rebase" do
        before { webhook_body[:comment][:body] = "@dependabot rebase?" }

        let(:dummy_rebase_handler) do
          instance_double(described_class::HandleRebaseRequest, run: nil)
        end

        before do
          allow(described_class::HandleRebaseRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_id: 301484237,
              comment_type: :issue_comment,
            ).
            and_return(dummy_rebase_handler)
        end

        it "delegates to HandleRebaseRequest" do
          expect(described_class::HandleRebaseRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_id: 301484237,
              comment_type: :issue_comment,
            ).
            and_return(dummy_rebase_handler)
          expect(dummy_rebase_handler).to receive(:run)
          perform_enqueued_jobs do
            action.run
          end
        end

        it "tags metrics with SLO" do
          frozen_time = Time.zone.parse("2017-05-15T14:02:03Z")
          expect(Time).to receive(:now).and_return(frozen_time).
            at_least(1).time
          expect(MetricsClient).
            to receive(:timing).
            with("issue_comment.age_at_reply", 4.0, tags: {
                   handler: "rebase_request",
                   slo_met: true,
                 })
          expect(MetricsClient).
            to receive(:timing).
            with("issue_comment.age_at_receive", 4.0, tags: {
                   handler: "rebase_request",
                   slo_met: true,
                 })
          perform_enqueued_jobs do
            action.run
          end
        end

        it "does not increments metrics for the handler type" do
          expect(MetricsClient).
            not_to receive(:increment).
            with("issue_comment.received")
          perform_enqueued_jobs do
            action.run
          end
        end

        it "increments metrics with a tag for the handler type" do
          expect(MetricsClient).
            to receive(:increment).
            with("issue_comment.received", tags: {
                   handler_name: "rebase_request",
                   user_type: "User",
                   performed_via_github_app: nil,
                 })
          action.run
        end

        context "when the payload includes a GitHub App" do
          let(:webhook_body) do
            hash = json_fixture("github_webhooks/issue_comment_github_app")
            hash.deep_symbolize_keys
          end

          it "increments metrics for the handler type" do
            expect(MetricsClient).
              to receive(:increment).
              with("issue_comment.received", tags: {
                     handler_name: "rebase_request",
                     user_type: "User",
                     performed_via_github_app: "comment_poster",
                   })
            action.run
          end
        end

        it "records the relevant traces" do
          allow(action.tracer).to receive(:in_span).and_call_original

          perform_enqueued_jobs do
            action.run
          end
          expect(action.tracer).to have_received(:in_span).
            with("HandleWebhook::IssueComment#handle_matched_commands")
        end

        context "missing .comment.created_at" do
          before { webhook_body[:comment].delete(:created_at) }

          it "invokes handler without metrics" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            expect(MetricsClient).not_to receive(:timing).
              with("issue_comment.age_at_reply", anything, anything)
            expect(MetricsClient).not_to receive(:timing).
              with("issue_comment.age_at_receive", anything, anything)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "when a bot" do
          before { webhook_body[:sender][:type] = "Bot" }

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "with random whitespace" do
          before do
            webhook_body[:comment][:body] = " @dependabot rebase?  please?"
          end

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end

          context "that includes a unicode whitespace character" do
            before { webhook_body[:comment][:body] = "@dependabot rebase?" }

            it "delegates to HandleRebaseRequest" do
              expect(described_class::HandleRebaseRequest).
                to receive(:new).
                with(
                  pull_request: pull_request,
                  requester: "greysteil",
                  comment_id: 301484237,
                  comment_type: :issue_comment,
                ).
                and_return(dummy_rebase_handler)
              expect(dummy_rebase_handler).to receive(:run)
              perform_enqueued_jobs do
                action.run
              end
            end
          end
        end

        context "when being polite" do
          before { webhook_body[:comment][:body] = "@dependabot rebase please" }

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "with `update` instead of `rebase`" do
          before do
            webhook_body[:comment][:body] = "@dependabot update"
          end

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "when being extra polite" do
          before { webhook_body[:comment][:body] = "@dependabot please rebase" }

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "when in code quotes" do
          before { webhook_body[:comment][:body] = "Use `@dependabot rebase`" }

          it "ignores the webhook" do
            expect(Dependabot::Logger).
              to receive(:info).
              with(hash_including(msg: /Ignoring/))
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "at the end of a sentence" do
          before do
            webhook_body[:comment][:body] = "Let's do this @dependabot rebase"
          end

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "when capitalizing" do
          before { webhook_body[:comment][:body] = "@Dependabot rebase\n\n" }

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "with a bullet" do
          before do
            webhook_body[:comment][:body] = "* @dependabot rebase please"
          end

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "with an html tag" do
          before do
            webhook_body[:comment][:body] = "<td>@dependabot rebase</td>"
          end

          it "delegates to HandleRebaseRequest" do
            expect(described_class::HandleRebaseRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_id: 301484237,
                comment_type: :issue_comment,
              ).
              and_return(dummy_rebase_handler)
            expect(dummy_rebase_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end
      end

      context "asking for a recreate" do
        before { webhook_body[:comment][:body] = "@dependabot recreate" }

        let(:dummy_recreate_handler) do
          instance_double(described_class::HandleRecreateRequest, run: nil)
        end

        before do
          allow(described_class::HandleRecreateRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_id: 301484237,
              comment_type: :issue_comment,
            ).
            and_return(dummy_recreate_handler)
        end

        it "delegates to HandleRecreateRequest" do
          expect(described_class::HandleRecreateRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_id: 301484237,
              comment_type: :issue_comment,
            ).
            and_return(dummy_recreate_handler)
          expect(dummy_recreate_handler).to receive(:run)
          perform_enqueued_jobs do
            action.run
          end
        end
      end

      context "asking for an ignore" do
        before { webhook_body[:comment][:body] = comment_body }

        let(:comment_body) { "@dependabot ignore this major version" }

        let(:dummy_ignore_handler) do
          instance_double(described_class::HandleIgnoreRequest, run: nil)
        end

        before do
          allow(described_class::HandleIgnoreRequest).to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_body: "@dependabot ignore this major version",
              comment_id: 301484237,
            ).
            and_return(dummy_ignore_handler)
        end

        it "delegates to HandleIgnoreRequest" do
          expect(described_class::HandleIgnoreRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_body: "@dependabot ignore this major version",
              comment_id: 301484237,
            ).
            and_return(dummy_ignore_handler)
          expect(dummy_ignore_handler).to receive(:run)
          perform_enqueued_jobs do
            action.run
          end
        end

        context "with square brackets" do
          let(:comment_body) { "@dependabot ignore this [major] version" }

          it "delegates to HandleIgnoreRequest" do
            expect(described_class::HandleIgnoreRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_body: "@dependabot ignore this [major] version",
                comment_id: 301484237,
              ).
              and_return(dummy_ignore_handler)
            expect(dummy_ignore_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "at the end of a sentence" do
          let(:comment_body) do
            "Closing for the same reason @dependabot ignore this major version"
          end

          it "delegates to HandleIgnoreRequest" do
            expect(described_class::HandleIgnoreRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_body: "Closing for the same reason @dependabot "\
                "ignore this major version",
                comment_id: 301484237,
              ).
              and_return(dummy_ignore_handler)
            expect(dummy_ignore_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end
      end

      context "asking for an unignore" do
        before { webhook_body[:comment][:body] = comment_body }

        let(:comment_body) { "@dependabot unignore business major version" }

        let(:dummy_unignore_handler) do
          instance_double(described_class::HandleUnignoreRequest, run: nil)
        end

        before do
          allow(described_class::HandleUnignoreRequest).to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_body: "@dependabot unignore business major version",
              comment_id: 301484237,
            ).
            and_return(dummy_unignore_handler)
        end

        it "delegates to HandleUnignoreRequest" do
          expect(described_class::HandleUnignoreRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_body: "@dependabot unignore business major version",
              comment_id: 301484237,
            ).
            and_return(dummy_unignore_handler)
          expect(dummy_unignore_handler).to receive(:run)
          perform_enqueued_jobs do
            action.run
          end
        end

        context "with dependency minor version" do
          let(:comment_body) { "@dependabot unignore business minor version" }

          it "delegates to HandleUnignoreRequest" do
            expect(described_class::HandleUnignoreRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_body: "@dependabot unignore business minor version",
                comment_id: 301484237,
              ).
              and_return(dummy_unignore_handler)
            expect(dummy_unignore_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end

          ["1.8.5", "1.8.a", "1.8.0-alpha.1"].each do |version|
            context "with dependency #{version} minor version" do
              let(:comment_body) { "@dependabot unignore business #{version} minor version" }

              it "delegates to HandleUnignoreRequest" do
                expect(described_class::HandleUnignoreRequest).
                  to receive(:new).
                  with(
                    pull_request: pull_request,
                    requester: "greysteil",
                    comment_body: "@dependabot unignore business #{version} minor version",
                    comment_id: 301484237,
                  ).
                  and_return(dummy_unignore_handler)
                expect(dummy_unignore_handler).to receive(:run)
                perform_enqueued_jobs do
                  action.run
                end
              end
            end
          end
        end

        context "with dependency name" do
          let(:comment_body) { "@dependabot unignore business" }

          it "delegates to HandleUnignoreRequest" do
            expect(described_class::HandleUnignoreRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_body: "@dependabot unignore business",
                comment_id: 301484237,
              ).
              and_return(dummy_unignore_handler)
            expect(dummy_unignore_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "with square brackets" do
          let(:comment_body) { "@dependabot unignore business [major] version" }

          it "delegates to HandleUnignoreRequest" do
            expect(described_class::HandleUnignoreRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_body: "@dependabot unignore business [major] version",
                comment_id: 301484237,
              ).
              and_return(dummy_unignore_handler)
            expect(dummy_unignore_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "at the end of a sentence" do
          let(:comment_body) do
            "Closing for the same reason @dependabot unignore business major version"
          end

          it "delegates to HandleUnignoreRequest" do
            expect(described_class::HandleUnignoreRequest).
              to receive(:new).
              with(
                pull_request: pull_request,
                requester: "greysteil",
                comment_body: "Closing for the same reason @dependabot "\
                "unignore business major version",
                comment_id: 301484237,
              ).
              and_return(dummy_unignore_handler)
            expect(dummy_unignore_handler).to receive(:run)
            perform_enqueued_jobs do
              action.run
            end
          end
        end

        context "when the comment is by dependabot" do
          let(:comment_body) do
            "Sorry, the command you entered is not valid. Valid commands:\n"\
              "`@dependabot unignore <dependency name> <ignore condition>`"
          end

          it "does not respond" do
            expect(described_class::HandleUnignoreRequest).not_to receive(:new)
            perform_enqueued_jobs do
              action.run
            end
          end
        end
      end

      context "asking for showing ignore conditions" do
        before { webhook_body[:comment][:body] = comment_body }

        let(:comment_body) { "@dependabot show business ignore conditions" }
        let(:dummy_ignore_show_handler) do
          instance_double(described_class::HandleIgnoreShowRequest, run: nil)
        end

        before do
          allow(described_class::HandleIgnoreShowRequest).to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_body: "@dependabot show business ignore conditions",
              comment_id: 301484237,
            ).
            and_return(dummy_ignore_show_handler)
        end

        it "delegates to HandleIgnoreShowRequest" do
          expect(described_class::HandleIgnoreShowRequest).
            to receive(:new).
            with(
              pull_request: pull_request,
              requester: "greysteil",
              comment_body: "@dependabot show business ignore conditions",
              comment_id: 301484237,
            ).
            and_return(dummy_ignore_show_handler)
          expect(dummy_ignore_show_handler).to receive(:run)
          perform_enqueued_jobs do
            action.run
          end
        end
      end

      context "that doesn't perform a command" do
        before { webhook_body[:comment][:body] = "Dave, wtf is this?" }

        before do
          allow(GitHubHelpers).to receive(:access_token_for)
        end

        it "ignores the webhook" do
          expect(Dependabot::Logger).
            to receive(:info).
            with(hash_including(msg: /Ignoring/))
          perform_enqueued_jobs do
            action.run
          end
        end
      end

      context "using slash command syntax" do
        [
          "/dependabot rebase",
          "/dependabot recreate",
          "/dependabot ignore this major version",
          "/dependabot ignore this minor version",
          "/dependabot ignore this dependency",
          "/dependabot ignore this package",
          "/dependabot ignore this",
          "/dependabot ignore these",
          "/dependabot ignore these dependencies",
          "/dependabot ignore these packages",
          "/dependabot ignore business major version",
          "/dependabot ignore business minor version",
          "/dependabot ignore business",
        ].each do |command|
          before do
            webhook_body[:comment][:body] = command
            allow(HandlePullRequestCommentJob).to receive(:perform_later)
          end

          it "#{command} enqueues a HandlePullRequestCommentJob" do
            action.run
            expect(HandlePullRequestCommentJob).to have_received(:perform_later)
          end
        end
      end

      context "when the comment is made by dependabot itself" do
        before do
          webhook_body[:comment][:user][:login] = "dependabot[bot]"
        end

        it "no-ops" do
          expect(Dependabot::Logger).not_to receive(:info)
          expect(MetricsClient).not_to receive(:timing).
            with("issue_comment.age_at_reply", anything, anything)
          expect(MetricsClient).not_to receive(:timing).
            with("issue_comment.age_at_receive", anything, anything)
          perform_enqueued_jobs do
            action.run
          end
        end
      end
    end

    describe "loving dependabot" do
      before do
        webhook_body[:comment][:body] = "@dependabot i love you!"
      end

      let(:dummy_heart_handler) do
        instance_double(described_class::HandleHeartRequest, run: nil)
      end

      it "delegates to HandleHeartRequest" do
        expect(described_class::HandleHeartRequest).
          to receive(:new).
          with(
            pull_request: pull_request,
            comment_id: 301484237,
            comment_type: :issue_comment,
          ).
          and_return(dummy_heart_handler)
        expect(dummy_heart_handler).to receive(:run)
        perform_enqueued_jobs do
          action.run
        end
      end
    end

    describe "metrics" do
      # Derived from fixtures/github_webhooks/issue_comment, which was created_at 2017-05-15T14:01:59Z
      let(:frozen_time) { Time.zone.parse("2017-05-15T14:02:59Z") }

      before do
        # Request a rebase, stub the implementation:
        webhook_body[:comment][:body] = "@dependabot rebase"
        dummy_rebase_handler = instance_double(described_class::HandleRebaseRequest, run: nil)
        allow(HandleWebhook::IssueComment::HandleRebaseRequest).
          to receive(:new).
          with(
            pull_request: pull_request,
            requester: "greysteil",
            comment_id: 301484237,
            comment_type: :issue_comment,
          ).
          and_return(dummy_rebase_handler)

        allow(Time).
          to receive(:now).
          and_return(frozen_time)
        allow(MetricsClient).to receive(:timing)
      end

      it "defaults to current time" do
        perform_enqueued_jobs do
          action.run
        end
        expect(Time).
          to have_received(:now).
          at_least(1).time
      end

      it "emits metrics" do
        perform_enqueued_jobs do
          action.run
        end

        # Event was received+replied exactly at frozen_time
        expect(MetricsClient).
          to have_received(:timing).
          with("issue_comment.age_at_receive", 60.0, tags: {
                 handler: "rebase_request",
                 slo_met: false,
               })
        expect(MetricsClient).
          to have_received(:timing).
          with("issue_comment.age_at_reply", 60.0, tags: {
                 handler: "rebase_request",
                 slo_met: false,
               })
      end

      context "with GLB request" do
        let(:x_request_start) { "t=1494856920000000" }
        let(:headers) { { "X-Request-Start" => x_request_start } }

        it "prefers X-Request-Start timing" do
          perform_enqueued_jobs do
            action.run
          end

          # Event was received at x_request_start, but replied at frozen_time
          expect(MetricsClient).
            to have_received(:timing).
            with("issue_comment.age_at_receive", 1.0, tags: {
                   handler: "rebase_request",
                   slo_met: true,
                 })
          expect(MetricsClient).
            to have_received(:timing).
            with("issue_comment.age_at_reply", 60.0, tags: {
                   handler: "rebase_request",
                   slo_met: false,
                 })
        end

        context "unexpected X-Request-Start timing" do
          let(:x_request_start) { "x=1494856920000000" }

          it "falls back to current time" do
            perform_enqueued_jobs do
              action.run
            end

            expect(MetricsClient).
              to have_received(:timing).
              with("issue_comment.age_at_receive", 60.0, tags: {
                     handler: "rebase_request",
                     slo_met: false,
                   })
          end
        end
      end
    end

    describe "activity monitoring", feature: :inactivity_pausing do
      before do
        allow(HandlePullRequestCommentJob).to receive(:perform_later)
        webhook_body[:comment][:body] = comment_body
      end

      context "with a supported command" do
        let(:comment_body) { "@dependabot rebase" }

        it "marks the repository as active" do
          repo.update(will_pause_at: 30.days.from_now.utc)

          perform_enqueued_jobs do
            expect { action.run }.
              to change { repo.reload.will_pause_at }.
              from(within(1.second).of(30.days.from_now.utc)).to(nil)
          end
        end
      end
    end

    describe "grouped update pull requests" do
      let(:comment_body) { "@dependabot hello!" }

      let(:dummy_unsupported_handler) do
        instance_double(described_class::HandleUnsupportedGroupedUpdateRequest, run: nil)
      end

      before do
        pull_request.update!(grouped_update: true)
        webhook_body[:comment][:body] = comment_body
      end

      it "still does nothing for a random comment" do
        expect(Dependabot::Logger).
          to receive(:info).
          with(hash_including(msg: /Ignoring/))
        expect(MetricsClient).not_to receive(:timing).
          with("issue_comment.age_at_reply", anything, anything)
        expect(MetricsClient).not_to receive(:timing).
          with("issue_comment.age_at_receive", anything, anything)
        perform_enqueued_jobs do
          action.run
        end
      end

      {
        "@dependabot rebase" => HandleWebhook::IssueComment::HandleRebaseRequest,
        "@dependabot recreate" => HandleWebhook::IssueComment::HandleRecreateRequest,
        "@dependabot ignore business major version" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore business minor version" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore business patch version" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore business" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore this" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore this dependency" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore this package" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore these" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore these dependencies" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore these packages" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore this major version" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore this minor version" => HandleWebhook::IssueComment::HandleIgnoreRequest,
        "@dependabot ignore this patch version" => HandleWebhook::IssueComment::HandleIgnoreRequest,
      }.each do |command_string, handler|
        context "with a supported comment of '#{command_string}'" do
          before do
            webhook_body[:comment][:body] = command_string
            allow(HandlePullRequestCommentJob).to receive(:perform_later)
          end

          it "enqueues a HandlePullRequestCommentJob for the action" do
            action.run
            expect(HandlePullRequestCommentJob).to have_received(:perform_later).with(
              hash_including(action: handler.to_s, requester_id: 1144873)
            )
          end
        end
      end
    end
  end
end
