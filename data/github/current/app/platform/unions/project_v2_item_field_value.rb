# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2ItemFieldValue < Platform::Unions::Base
      docs_category :projects
      description "Project field values"

      visibility :public, environments: [:dotcom, :enterprise]

      possible_types(
        Objects::ProjectV2ItemFieldTextValue,
        Objects::ProjectV2ItemFieldNumberValue,
        Objects::ProjectV2ItemFieldDateValue,
        Objects::ProjectV2ItemFieldSingleSelectValue,
        Objects::ProjectV2ItemFieldRepositoryValue,
        Objects::ProjectV2ItemFieldUserValue,
        Objects::ProjectV2ItemFieldLabelValue,
        Objects::ProjectV2ItemFieldMilestoneValue,
        Objects::ProjectV2ItemFieldPullRequestValue,
        Objects::ProjectV2ItemFieldIterationValue,
        Objects::ProjectV2ItemFieldReviewerValue,
        Objects::ProjectV2ItemIssueFieldValue,
      )
    end
  end
end
