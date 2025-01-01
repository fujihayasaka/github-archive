# typed: true
# frozen_string_literal: true

module Discussions
  class LabelsController < Discussions::BaseController
    before_action :require_xhr
    before_action :require_discussion, only: :update
    before_action :require_labelable, only: :update

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Iam,
      only: [:search_menu]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Iam,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show, :search_menu], optional: true

    def show
      render Discussions::LabelsMenuContentComponent.new(
        repository: current_repository,
        discussion: existing_or_new_discussion,
      ), layout: false
    end

    def sidebar_item # rubocop:todo GitHub/UseRestfulActions
      render Discussions::LabelsComponent.new(
        repository: current_repository,
        discussion: existing_or_new_discussion,
        can_edit_labels: existing_or_new_discussion.labelable_by?(current_user),
        defer_menu_content: false,
        org_param: org_param,
      ), layout: false
    end

    def search_menu # rubocop:todo GitHub/UseRestfulActions
      render Discussions::LabelSearchContentComponent.new(
        repository: current_repository,
        parsed_query: parsed_discussions_query,
        org_param: org_param,
      ), layout: false
    end

    def update
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      if current_repository.locked_on_migration? || current_repository.archived?
        head :unprocessable_entity
        return
      end

      label_ids = params[:discussion][:labels]
      labels = if label_ids.any?
        if GitHub.flipper[:issue_dependency_removal].enabled?
          Issues.domain.labels.by_repository_and_normalized_ids(repository_id: T.must(current_repository.id), label_ids:)
        else
          current_repository.load_labels(label_ids)
        end
      else
        []
      end
      discussion.replace_labels(labels)

      respond_to do |format|
        format.html do
          render Discussions::LabelsComponent.new(
            repository: current_repository,
            discussion: discussion,
            can_edit_labels: true, # This action is guarded with require_labelable
            org_param: org_param,
          ), layout: false
        end
      end
    end

    private

    def require_xhr
      render_404 unless request.xhr?
    end

    def require_labelable
      head :forbidden unless discussion&.labelable_by?(current_user)
    end

    def existing_or_new_discussion
      return discussion if discussion

      discussion_params = params.fetch(:discussion, {})

      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      @discussion = current_repository.discussions.new

      if discussion_params.has_key?(:labels)
        @discussion.labels = if GitHub.flipper[:issue_dependency_removal].enabled?
          Issues.domain.labels.by_repository_and_normalized_ids(
            repository_id: T.must(current_repository.id),
            label_ids: discussion_params[:labels]
          )
        else
          current_repository.load_labels(discussion_params[:labels])
        end
      end

      @discussion
    end
  end
end
