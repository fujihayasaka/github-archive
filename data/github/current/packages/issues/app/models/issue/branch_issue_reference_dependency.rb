# typed: true
# frozen_string_literal: true

module Issue::BranchIssueReferenceDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Issue))

    has_many :linked_branches, class_name: "BranchIssueReference"
    destroy_dependents_in_background :linked_branches
  end
end
