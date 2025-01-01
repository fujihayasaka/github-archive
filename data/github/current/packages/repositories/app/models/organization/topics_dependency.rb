# typed: false
# frozen_string_literal: true

module Organization::TopicsDependency
  def repositories_with_topic_manage_access(viewer:)
    unless viewer
      return ::Repository.none
    end

    contribution_classes = Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS
    contributions_collector = Contribution::Collector.new(
      user: viewer,
      time_range: 1.year.ago..Time.zone.now,
      contribution_classes: contribution_classes,
      viewer: viewer,
      organization_id: self.id
    )
    contributed_repo_ids = contributions_collector.visible_repository_ids
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    adminable_repo_ids = viewer.associated_repository_ids(min_action: :admin, organization: self)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    repo_ids = contributed_repo_ids & adminable_repo_ids

    visible_repositories_for(viewer).where(id: repo_ids).order(:name).filter_spam_and_disabled_for(viewer)
  end
end
