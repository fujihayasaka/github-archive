# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Labels < Resolvers::Base
      MAX_LABELS_IN_NAME_FILTER = 20

      type Connections.define(Objects::Label), null: true

      argument :order_by, Inputs::LabelOrder, "Ordering options for labels returned from the connection.", required: false,
        default_value: { field: "created_at", direction: "ASC" }

      argument :names, String, "Filter labels by their exact names in a comma separated string. Only the first #{MAX_LABELS_IN_NAME_FILTER} names will be used.", required: false, visibility: :internal

      def resolve(order_by:, query: nil, **arguments)
        async_has_permission?.then do |has_permission|
          next ::Label.none unless has_permission

          # query is added by one of the fields, this will probably be broken
          if query.present? && object.is_a?(Repository)
            search_labels(query, repository: object)
          else
            # Batch-load all labels for the object then sort them in memory,
            # trading a small amount of possible overfetching to eliminate an
            # N+1. The tradeoff is worth it when the number of labels is tiny,
            # which is pretty much all of the time.
            async_labels.then do |labels|
              filtered_labels = case object
              when IssueTemplate
                label_names = extract_labels_from_string(object.labels_string)
                labels.select { |label| label_names.include?(label.name) }
              else
                if arguments[:names].present?
                  label_names = extract_labels_from_string(arguments[:names])
                  labels.select { |label| label_names.include?(label.name) }
                else
                  labels
                end
              end
              in_memory_sort(labels: filtered_labels, order_by:)
            end
          end
        end
      end

      private

      def extract_labels_from_string(labels_string)
        current_labels_string = labels_string
        label_values = []

        # Extract all of the values enclosed in quotation marks
        current_labels_string.scan(/"([^"]+)"/) do |match|
          val = match[0].strip
          label_values << val
        end


        # Remove all of the values enclosed in quotation marks
        current_labels_string = current_labels_string.gsub(/"([^"]+)"/, "")

        # Extract all of the (un-escaped) comma-separated values
        current_labels_string.scan(/([^,]+)/) do |match|
          val = match[0].strip
          if !val.empty?
            label_values << val
          end
        end

        label_values.take(MAX_LABELS_IN_NAME_FILTER)
      end

      def in_memory_sort(labels:, order_by:)
        sorted = case order_by.field
        when "created_at"
          if GitHub.flipper[:label_sort_handle_nil].enabled?
            labels.compact.sort_by { |label| label&.created_at || Time.at(0) }
          else
            labels.sort_by(&:created_at)
          end
        when "name"       then GitHub.flipper[:case_insensitive_label_ordering_gql].enabled? ? labels.sort_by { |label| label.name.downcase } : labels.sort_by(&:name)
        when "issue_count"
          labels.sort_by { |label| label.issues_count.to_i } # domain-isolation-query-violation:ignore:packages/issues (select)
        else
          raise Platform::Errors::Internal, "unknown order_by field #{order_by.field}, expected one of Platform::Enums::LabelOrderField"
        end

        sorted.reverse! if order_by.direction == "DESC"
        ArrayWrapper.new(sorted)
      end

      def async_has_permission?
        case object
        when Repository
          context[:permission].async_can_list_repo_labels?(object)
        when PullRequest, Issue, Discussion
          context[:permission].typed_can_access?(object.class.name, object)
        when IssueTemplate
          context[:permission].async_can_list_repo_labels?(object.repository)
        end
      end

      def async_labels
        case object
        when Repository, Issue, Discussion then object.async_labels
        when PullRequest                   then object.async_issue.then(&:async_labels)
        when IssueTemplate                 then
          # An issue template's repository can be the global .github repository,
          # which might not be the current repository in which the issue is created.
          # In that case, we need to fetch the labels from the repository of the issue,
          # which is added to the template in the repository resolver for the templates.
          object.current_repository&.async_labels || object.async_repository.then(&:async_labels)
        else
          raise Platform::Errors::Internal, "don't know how to fetch labels for #{object.class}"
        end
      end

      def search_labels(phrase, repository:)
        Search::Queries::LabelQuery.new(phrase: phrase, raw_phrase: phrase, repo_id: repository.id, current_user: context[:viewer])
      end
    end
  end
end
