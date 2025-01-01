# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of imported labels data.
      class ImportLabelsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        MAX_THROTTLE_RETRIES = 5

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportLabelsAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the ImportLabels Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportLabelsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportLabelsResponse, or a Twirp::Error.
        def import_labels(req, env)
          check_model_replication_delay!(Label)

          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.labels.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "labels")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          errors = []

          labels = req.labels.map.with_index do |label_req, index|
            next if label_exists_with(repository, label_req.name)

            # default to sample color when not specified
            label_color = label_req.color.empty? ? generate_sample_color : label_req.color

            label = repository.labels.build(
              name: label_req.name,
              label_name: label_req.name,
              color: label_color,
              description: label_req.description,
              created_at: Time.current,
              updated_at: Time.current,
            )

            # Skip invalid labels for now
            if !label.valid?
              errors << { batch_index: index, error_message: "invalid label"  }
              next
            end

            { "color": label.color }.merge(label.attributes) # re-order hash so the first key isn't a vindex column
          end.compact

          Label.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
            ActiveRecord::Base.connected_to(role: :writing) do
              Label.insert_all(labels)
            end
          end if labels.any?

          # Returns errors if any
          { batch_validation_errors: errors }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the AddLabelsToIssue Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::AddLabelsToIssueRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::AddLabelsToIssueResponse, or a Twirp::Error.
        def add_labels_to_issue(req, env)
          check_model_replication_delay!(Label)

          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.issue_number.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "issue_number")
          end

          if req.labels.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "labels")
          end

          if req.labels.count >= Issue::LABEL_LIMIT
            return Twirp::Error.invalid_argument("can have a maximum of #{Issue::LABEL_LIMIT} labels", argument: "labels")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          issue = replica(Issue).find_by(repository: repository, number: req.issue_number)

          unless issue
            return Twirp::Error.not_found("Issue associated with the repository is not found.", argument: "issue_number", value: req.issue_number.to_s)
          end

          Label.transaction do
            ActiveRecord::Base.connected_to(role: :writing) do
              req.labels.each do |label_name|
                label = issue.repository.labels.with_name(label_name).first
                issue.labels << label unless issue.labels.any?(label)
              end
            end
          end

          # Returns nothing
          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def label_exists_with(repository, label_name)
          repository.labels.with_name(label_name).exists?
        end

        def generate_sample_color
          Label.defaults.sample.color
        end
      end
    end
  end
end
