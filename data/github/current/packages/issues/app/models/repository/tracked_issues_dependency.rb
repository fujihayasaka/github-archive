# typed: true
# frozen_string_literal: true
module Repository::TrackedIssuesDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Public: should the checklist data be extracted into nested issues (issue_links table)?
  def extract_checklists_enabled?
    return @extract_checklists_enabled if defined?(@extract_checklists_enabled)
    @extract_checklists_enabled = feature_enabled_for_repo_or_org(:extract_checklists)
  end

  def feature_enabled_for_repo_or_org(feature_name)
    self.feature_enabled?(feature_name, memoize: false) || (self.owner&.organization? && GitHub.flipper[feature_name].enabled?(self.owner))
  end
end
