# frozen_string_literal: true

require "dependabot/pull_request_creator/labeler"

module HandleWebhook
  class Label
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      return unless dependabot_label_change?
      return unless active_repo?

      UpdateDefaultLabelsJob.perform_later(repo: repo)
    end

    private

    def dependabot_label_change?
      dependencies_label_regex =
        Dependabot::PullRequestCreator::Labeler::DEPENDENCIES_LABEL_REGEX
      return true if label_name.match?(dependencies_label_regex)

      language_labels =
        Dependabot::PullRequestCreator::Labeler.package_manager_labels.
        values.map { |h| h.fetch(:name) }

      language_labels.any? { |l| l.casecmp(label_name).zero? }
    end

    def label_name
      @label_name ||= webhook_body[:label][:name]
    end

    def active_repo?
      repo && repo.update_configs.active.any?
    end

    def repo
      @repo ||= Repo.find_by(github_id: webhook_body[:repository][:id])
    end
  end
end
