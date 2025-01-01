# typed: true
# frozen_string_literal: true

module GitHub
  module Importer2
    class Issues
      def push(repo:, current_user:, issue_data:)
        ImportItem.create! do |item|
          item.repository = repo
          item.user = current_user
          item.model_type = "issue"
          item.status = "pending"
          item.data = issue_data
        end.tap do |item|
          ::ImportIssueJob.enqueue(item)
        end
      end

      def get(repo:, current_user:, id:)
        ImportItem.where(repository_id: repo.id).find_by(id: id)
      end

      def get_all(repo:, current_user:, updated_since:)
        scope = ImportItem.where(repository_id: repo.id)
        if updated_since
          scope = scope.where("updated_at > ?", updated_since)
        end
        scope.order("updated_at")
      end

      # Don't call this from a unicorn!
      def create_issue(import_item)
        ::GitHub::Importer2::IssueCreator.new(import_item).import!
      end
    end
  end
end
