# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module IssuesBulkUpdate
        def construct_job_params(inputs)
          job_params = {}
          job_params[:state] = inputs[:state] if inputs.key?(:state)
          job_params[:state_reason] = inputs[:state_reason] if inputs.key?(:state_reason)

          if inputs.key?(:remove_labels) || inputs.key?(:apply_labels)
            label_hash = {}
            label_hash.merge!(inputs[:apply_labels].map { |l| [l.id.to_s, "1"] }.to_h) if inputs.key?(:apply_labels)
            label_hash.merge!(inputs[:remove_labels].map { |l| [l.id.to_s, "0"] }.to_h) if inputs.key?(:remove_labels)
            job_params[:labels] = label_hash
          end

          if inputs.key?(:remove_assignees) || inputs.key?(:apply_assignees)
            assignee_hash = {}
            assignee_hash.merge!(inputs[:apply_assignees].map { |l| [l.id.to_s, "1"] }.to_h) if inputs.key?(:apply_assignees)
            assignee_hash.merge!(inputs[:remove_assignees].map { |l| [l.id.to_s, "0"] }.to_h) if inputs.key?(:remove_assignees)
            job_params[:assignees] = assignee_hash
          end

          if inputs.key?(:milestone)
            job_params[:milestone] = inputs[:milestone].id
          elsif inputs.key?(:clear_milestone) && inputs[:clear_milestone]
            # setting it to id 0 which does not exist to remove the milestone
            job_params[:milestone] = 0
          end

          if inputs.key?(:issue_type)
            job_params[:issue_type] = inputs[:issue_type].id
          elsif inputs.key?(:unset_issue_type) && inputs[:unset_issue_type]
            job_params[:issue_type] = 0
          end

          if inputs.key?(:remove_from_project_v2s) || inputs.key?(:add_to_project_v2s)
            projects_hash = {}
            projects_hash.merge!(inputs[:add_to_project_v2s].map { |l| [l.id.to_s, "on"] }.to_h) if inputs.key?(:add_to_project_v2s)
            projects_hash.merge!(inputs[:remove_from_project_v2s].map { |l| [l.id.to_s, "off"] }.to_h) if inputs.key?(:remove_from_project_v2s)
            job_params[:projects] = projects_hash
          end

          job_params
        end

        def get_issue_count_tag(size)
          if size < 2
            "0_to_1"
          elsif size < 5
            "1_to_5"
          elsif size < 25
            "5_to_25"
          elsif size < 50
            "25_to_50"
          elsif size < 100
            "50_to_100"
          elsif size < 500
            "100_to_500"
          else
            "500_to_#{Platform::Inputs::IssueBulkInput::MAX_ISSUES}"
          end
        end

        def get_tags(inputs, count)
          [
            "is_changing_state:#{inputs.key?(:state) || inputs.key?(:state_reason)}",
            "is_adding_labels:#{inputs.key?(:apply_labels)}",
            "is_removing_labels:#{inputs.key?(:remove_labels)}",
            "is_adding_assignees:#{inputs.key?(:apply_assignees)}",
            "is_removing_assignees:#{inputs.key?(:remove_assignees)}",
            "is_adding_to_project:#{inputs.key?(:add_to_project_v2s)}",
            "is_removing_from_project:#{inputs.key?(:remove_from_project_v2s)}",
            "is_adding_milestone:#{inputs.key?(:milestone)}",
            "is_removing_milestone:#{inputs.key?(:clear_milestone)}",
            "is_setting_issue_type:#{inputs.key?(:issue_type)}",
            "is_unsetting_issue_type:#{inputs.key?(:unset_issue_type)}",
            "issues_count:#{get_issue_count_tag(count)}"
          ]
        end
      end
    end
  end
end
