# typed: true
# frozen_string_literal: true

module User::IssueTypesDependency
  include GitHub::BatchMethod
  extend ActiveSupport::Concern
  extend T::Helpers

  BATCH_LIMIT = 1000

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    # This method is intended for use when the viewer is only fetching their own
    # issue type suggestions, so we can return then as filtering suggestions in the '/issues' dashboard.
    # If this method is being used to return  suggestions for groups of users, it is not optimized to
    # prevent n+1 queries for the user.organizations calls that would happen per user.
    # See the comments here https://github.com/github/github/pull/322153 for more info.
    batch_method :accessible_suggested_issue_type_names do |users, viewer, cap_filter|
      authorized_org_ids_for_viewer = cap_filter.authorized_resource_ids(viewer.organizations)

      results = users.map do |user|
        org_ids = user.organization_ids_visible_to(viewer)
        next [] if org_ids.empty?

        authorized_organization_ids = org_ids.select { |id| authorized_org_ids_for_viewer.include?(id) }
        next [] if authorized_organization_ids.empty?

        issue_types = []
        IssueType.distinct.select(:name).where(owner: authorized_organization_ids, enabled: true).in_batches(of: BATCH_LIMIT) do |types|
          issue_types << types.pluck(:name)
        end
        issue_types.flatten
      end

      users.zip(results).to_h
    end
  end

  sig { returns(T::Boolean) }
  def issue_types_enabled?
    false
  end
end
