# typed: true
# frozen_string_literal: true

class MagicShell
  extend T::Sig

  DATA_DELEGATIONS = {
    open_classic_projects_count: Strategies::OpenClassicProjectsCount,
    open_repo_issue_count_for_viewer: Strategies::OpenRepoIssueCountForViewer,
    accessibility_link_underlines_enabled?: Strategies::AccessibilityLinkUnderlinesEnabled,
  }

  sig { params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).void }
  def initialize(viewer, repository)
    @viewer = viewer
    @repository = repository
  end

  def self.data_delegations
    DATA_DELEGATIONS
  end

  DATA_DELEGATIONS.each do |method_name, denormalization_strategy|
    self.class_eval do
      define_method(method_name) do
        denormalization_strategy.new.call(@viewer, @repository)
      end
    end
  end
end
