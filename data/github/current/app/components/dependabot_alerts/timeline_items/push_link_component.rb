# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class PushLinkComponent < ApplicationComponent
    COMMIT_SHA_LENGTH = 7

    attr_reader :alert, :push

    def initialize(alert:, push:)
      @alert = alert
      @push = push
    end

    def call
      text = single_commit? ? after_sha : "#{before_sha}..#{after_sha}"

      content_tag :code, render(Primer::Beta::Link \
        .new(href: push_path, schema: :primary, bg: :accent , px: 2, py: 1, border_radius: 3, test_selector: "push-diff-link")
        .with_content(text)
      )
    end

    private

    def after_sha
      push.after.first(COMMIT_SHA_LENGTH)
    end

    def before_sha
      push.before.first(COMMIT_SHA_LENGTH)
    end

    def single_commit?
      push_commits == 1
    end

    memoize def push_commits
      begin
        comparison = GitHub::Comparison.from_range(alert.repository, "#{push.before}..#{push.after}")
        comparison.total_commits
      rescue GitRPC::Error
        # If GitRPC fails, return 0 so we can fail gracefully and not take down the Alert#show page.
        0
      end
    end

    def push_path
      if single_commit?
        "#{alert.repository.permalink(include_host: true)}/commit/#{push.after}"
      else
        push.permalink
      end
    end
  end
end
