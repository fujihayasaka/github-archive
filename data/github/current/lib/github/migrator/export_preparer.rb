# typed: true
# frozen_string_literal: true

# ExportPreparer is a service object that will prepare a Repository
# and its dependencies to be exported.
#
# To prepare the Repository, a MigratableResource  with the migration's
# guid will be created for the Repository and each of its dependent
# models.
#
# The dependencies of a Repository are defined as:
# - The Repository's owner (Organization)
# - All of that Organization's Teams
# - All of that Organization's Members
# - All of that Organization's Projects
# - The Repository's Milestones
# - The Repository's CommitComments
# - The Repository's Issues
# - The Repository's PullRequests
# - All of the PullRequests' ReviewComments
# - All of the Issues' Comments
# - All of the Repository's Projects
# - All of the Repository's Discussions
# - All of the Discussion's Categories
# - All of the Discussion's Comments
module GitHub
  class Migrator
    class ExportPreparer
      BATCH_SIZE = 1000
      COMMIT_COMMENT_BATCH_SIZE = 500

      # Public: Instantiates an ExportPreparer for the given repository and the migration
      # represented by guid.
      #
      # repository (Required) - Repository that will be exported to an archive.
      # guid (Required)       - A unique identifier representing the migration this model
      #                         will be prepared for.
      # options values:
      # events:               - An instance of GitHub::Migrator::Events that will notify its
      #                         subscribers of progress.
      # exclude_metadata      - If true, will exclude metadata and only contain git source. Default to false.
      # exclude_attachments   - If true, will not include attachments. Defaults to false.
      # exclude_releases      - If true, will not include releases. Defaults to false.
      # exclude_owner_projects - If true, will not include owner-level projects. Defaults to false.
      # exclude_projects      - If true, will not include org and repo projects. Defaults to false.
      # lock_repository       - If true, lock the repository for the duration of the action.
      #                         Defaults to false.
      #
      def initialize(repository:, guid:, options: nil)
        options ||= {}
        @repository             = repository
        @guid                   = guid
        @lock_repository        = options.fetch(:lock_repository, false)
        @exclude_metadata       = options.fetch(:exclude_metadata, false)
        @exclude_attachments    = options.fetch(:exclude_attachments, false)
        @exclude_releases       = options.fetch(:exclude_releases, false)
        @exclude_git_data       = options.fetch(:exclude_git_data, false)
        @exclude_owner_projects = options.fetch(:exclude_owner_projects, false)
        @events                 = options.fetch(:events) { GitHub::Migrator::Events::Null.new }
        @cache                  = GitHub::Migrator::Cache.new
        @exclude_projects       = options.fetch(:exclude_projects, false)
      end

      # Public: Execute the action. Creates all of the MigratableResources for the
      # given Repository and its dependencies.
      #
      # Raises an exception if any required options are not present.
      #
      # Returns a Hash with a count of each model type that is prepared for exporting.
      def call
        validate
        # Get the top-level repo to be migrated, lock repo if lock was requested
        ActiveRecord::Base.connected_to(role: :writing) do
          repository.lock_for_migration if lock_repository
        end

        owner = repository.owner

        # Create MigratableResources for the Repository and its dependents
        export_builder.add(repository)

        # For Octoshift migrations, we want the exporter to create archives that only includes the git
        # source data and handle metadata without another export that only includes metadata
        unless exclude_metadata
          add_repository_collaborators(repository)
          add_owner_teams_and_members(owner) unless exclude_git_data
          add_owner_projects(owner)
          add_protected_branches(repository)
          add_repository_projects(repository)
          add_milestones(repository)
          add_commit_comments(repository)

          issue_ids = issue_ids_for_repository(repository)
          add_issues(issue_ids)

          pull_request_ids = pull_request_ids_for_repository(repository)
          add_pull_requests(pull_request_ids)
          add_pull_request_reviews(pull_request_ids)
          add_pull_request_review_threads(pull_request_ids)
          add_pull_request_review_comments(pull_request_ids)
          add_pull_request_review_requests(pull_request_ids)

          all_issue_ids = all_issue_ids_for_repository(repository)
          add_issue_comments(all_issue_ids)
          add_issue_events(all_issue_ids, owner)

          add_releases(repository)
          add_repository_files(repository)

          discussion_ids = repository.discussions.pluck(:id)
          add_discussions(discussion_ids)
          add_discussion_comments(discussion_ids)

          discussion_category_ids = repository.discussion_categories.pluck(:id)
          add_discussion_categories(discussion_category_ids)
        end

        # Finalize
        attachment_migrator.complete
        export_builder.complete

        # Generate report hash and return
        migratable_resources = MigratableResource.for_guid(guid)
        GitHub::Migrator::MigrationReporter.migrator_result(migratable_resources)
      ensure
        cache.clear
      end

      private

      attr_reader :repository, :cache, :events, :guid, :lock_repository, :exclude_metadata, :exclude_git_data, :exclude_attachments, :exclude_releases, :exclude_owner_projects, :exclude_projects

      # validate that required options are present
      def validate
        if repository.nil?
          raise GitHub::Migrator::RepositoryRequired
        end
        if guid.nil?
          raise GitHub::Migrator::GuidRequired
        end
      end

      def export_builder
        @export_builder ||= GitHub::Migrator::MigratableResourceExportBuilder.new \
          guid: guid,
          model_url_service: GitHub::Migrator::ModelUrlService.new(cache: cache),
          progress: lambda { |*x| events.fire(*x) }
      end

      def attachment_migrator
        @attachment_migrator ||=
          if exclude_attachments
            GitHub::Migrator::AttachmentMigrator::Null.new
          else
            GitHub::Migrator::AttachmentMigrator.new(export: export_builder)
          end
      end

      def add_repository_collaborators(repository)
        repository.members.find_each do |user|
          export_builder.add(user)
        end
      end

      def add_owner_teams_and_members(owner)
        export_builder.add(owner)

        if owner.try(:organization?)
          owner.members.find_each do |user|
            export_builder.add(user)
          end

          parent_root_teams = owner.teams.with_no_parent

          parent_and_then_child_teams = []
          if parent_root_teams.present?
            parent_root_teams.each do |team|
              parent_and_then_child_teams << team
              team.descendants_depth_first.each do |child_team|
                parent_and_then_child_teams << child_team
              end
            end
          end

          export_teams = parent_and_then_child_teams.blank? ? owner.teams.to_a : parent_and_then_child_teams

          export_teams.each do |team|
            export_builder.add(team)

            team.members.find_each do |user|
              export_builder.add(user)
            end
          end
        end
      end

      def add_owner_projects(owner)
        return if exclude_projects || exclude_owner_projects

        if owner.try(:organization?)
          owner.projects.find_each do |project|
            export_builder.add(project)
            export_builder.add(project.creator)
          end
        end
      end

      def add_issues(issue_ids)
        issue_ids.each_slice(BATCH_SIZE) do |issue_batch_ids|
          Issue.where(id: issue_batch_ids).find_each do |issue|
            export_builder.add(issue)
            export_builder.add(user_id: issue.user_id)
            attachment_migrator.push(issue)
          end
        end
      end

      def add_pull_requests(pull_request_ids)
        pull_request_ids.each_slice(BATCH_SIZE) do |pull_request_batch_ids|
          PullRequest.includes(:issue).where(id: pull_request_batch_ids).find_each do |pull_request|
            export_builder.add(pull_request)
            export_builder.add(user_id: pull_request.user_id)
            attachment_migrator.push(pull_request.issue)
          end
        end
      end

      def add_pull_request_reviews(pull_request_ids)
        pull_request_ids.each_slice(BATCH_SIZE) do |pull_request_batch_ids|
          PullRequestReview.where(pull_request_id: pull_request_batch_ids).find_each do |review|
            export_builder.add(review)
            export_builder.add(user_id: review.user_id)
            attachment_migrator.push(review)
          end
        end
      end

      def add_pull_request_review_threads(pull_request_ids)
        pull_request_ids.each_slice(BATCH_SIZE) do |pull_request_batch_ids|
          PullRequestReviewThread.where(pull_request_id: pull_request_batch_ids).find_each do |review_thread|
            export_builder.add(review_thread)
            export_builder.add(user_id: review_thread.resolver_id)
          end
        end
      end

      def add_pull_request_review_comments(pull_request_ids)
        pull_request_ids.each_slice(BATCH_SIZE) do |pull_request_batch_ids|
          PullRequestReviewComment.where(pull_request_id: pull_request_batch_ids).find_each do |review_comment|
            export_builder.add(review_comment)
            export_builder.add(user_id: review_comment.user_id)
            attachment_migrator.push(review_comment)
          end
        end
      end

      def add_pull_request_review_requests(pull_request_ids)
        pull_request_ids.each_slice(BATCH_SIZE) do |pull_request_batch_ids|
          ReviewRequest
            .where(pull_request_id: pull_request_batch_ids, reviewer_type: "User")
            .pluck(:reviewer_id)
            .each { |reviewer_id| export_builder.add(user_id: reviewer_id) }
        end
      end

      def add_issue_comments(issue_ids)
        issue_ids.each_slice(BATCH_SIZE) do |issue_batch_ids|
          IssueComment.where(issue_id: issue_batch_ids).find_each do |comment|
            export_builder.add(comment)
            export_builder.add(user_id: comment.user_id)
            attachment_migrator.push(comment)
          end
        end
      end

      def add_issue_events(issue_ids, owner)
        # Useful for checking whether a model belongs to a repo in the org.
        owner_repository_ids = owner.repositories.pluck(:id)
        owner_project_ids = owner.projects.pluck(:id)

        issue_ids.each_slice(BATCH_SIZE) do |issue_batch_ids|
          IssueEvent.where(issue_id: issue_batch_ids).includes(:issue).find_each do |event|
            # TODO: Remove this once IssueEvent is properly typed
            event = T.unsafe(event)

            # Skip exporting deployment issue events until we add support.
            # See https://github.com/github/github/issues/98221
            next if event.deployment_id
            next if skip_review_point_events?(event)
            next if skip_project_events?(event)
            next if skip_owner_project_events?(event, owner_project_ids)
            next if skip_discussion_events?(event)

            if event.commit_repository_id
              next unless owner_repository_ids.include?(event.commit_repository_id)
            end

            export_builder.add(event)
            export_builder.add(user_id: event.actor_id)
            export_builder.add(user_id: event.subject_id) if event.subject_type == "User"
          end
        end
      end

      def skip_project_events?(event)
        exclude_projects && IssueEvent::PROJECT_EVENTS.include?(event.event)
      end

      def skip_review_point_events?(event)
        event.event == "ready_for_review" && event.subject_type == "PRReviewPoint"
      end

      def skip_owner_project_events?(event, owner_project_ids)
        exclude_owner_projects &&
        IssueEvent::PROJECT_EVENTS.include?(event.event) &&
        owner_project_ids.include?(event.subject_id)
      end

      def skip_discussion_events?(event)
        event.event == "converted_to_discussion" && event.subject_type == "Discussion"
      end

      def add_milestones(repository)
        repository.milestones.find_each do |milestone|
          export_builder.add(milestone)
          export_builder.add(user_id: milestone.user_id) if milestone.user.present?
        end
      end

      def add_protected_branches(repository)
        repository.protected_branches.find_each do |protected_branch|
          export_builder.add(protected_branch)
          export_builder.add(user_id: protected_branch.creator_id)
        end
      end

      def add_repository_projects(repository)
        return if exclude_projects

        repository.projects.find_each do |project|
          export_builder.add(project)
          export_builder.add(project.creator)
        end

        add_project_card_creators(repository.projects.pluck(:id))
      end

      def add_project_card_creators(project_ids)
        project_ids.each_slice(BATCH_SIZE) do |project_batch_ids|
          ProjectCard.where(project_id: project_batch_ids).find_each do |project_card|
            export_builder.add(user_id: project_card.creator_id)
          end
        end
      end

      def add_commit_comments(repository)
        commit_comment_ids = repository.commit_comments.pluck(:id)

        commit_comment_ids.each_slice(COMMIT_COMMENT_BATCH_SIZE) do |commit_comment_batch_ids|
          CommitComment.where(id: commit_comment_batch_ids).find_each do |commit_comment|
            export_builder.add(commit_comment)
            export_builder.add(user_id: commit_comment.user_id)
            attachment_migrator.push(commit_comment)
          end
        end
      rescue ActiveRecord::StatementInvalid => error
        GitHub.logger.error("Skipping commit comments export due to exhausted resources", {
          :exception => error,
          "code.function" => "add_commit_comments",
          "code.namespace" => "GitHub::Migrator::ExportPreparer",
          "gh.migration_tools.migration.type" => "repo",
          "gh.migration_tools.migration.guid" => @guid,
          "gh.migration_tools.migration.resolution" => "skipped"
          }
        )
      end

      def add_releases(repository)
        return if exclude_releases

        repository.releases.each do |release|
          export_builder.add(release)
          export_builder.add(user_id: release.author_id)
        end
      end

      def add_repository_files(repository)
        repository.repository_files.each do |repository_file|
          next unless repository_file.uploaded?
          export_builder.add(repository_file)
          export_builder.add(user_id: repository_file.uploader_id)
        end
      end

      def add_discussions(discussion_ids)
        discussion_ids.each_slice(BATCH_SIZE) do |discussion_batch_ids|
          Discussion.where(id: discussion_batch_ids).find_each do |discussion|
            export_builder.add(discussion)
            export_builder.add(user_id: discussion.user_id)
            attachment_migrator.push(discussion)
          end
        end
      end

      def add_discussion_categories(discussion_category_ids)
        discussion_category_ids.each_slice(BATCH_SIZE) do |discussion_category_batch_ids|
          DiscussionCategory.where(id: discussion_category_batch_ids).find_each do |discussion_category|
            export_builder.add(discussion_category)
          end
        end
      end

      def add_discussion_comments(discussion_ids)
        discussion_ids.each_slice(BATCH_SIZE) do |discussion_batch_ids|
          DiscussionComment.where(discussion_id: discussion_batch_ids).find_each do |discussion_comment|
            export_builder.add(discussion_comment)
            export_builder.add(user_id: discussion_comment.user_id)
            attachment_migrator.push(discussion_comment)
          end
        end
      end

      def pull_request_ids_for_repository(repository)
        pull_request_ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = repository.issues.with_pull_requests.limit(100_000).order(:pull_request_id)
        batch_ids = batch_scope.where("pull_request_id > ?", last_batch_id).pluck(:pull_request_id)

        while batch_ids.any?
          pull_request_ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("pull_request_id > ?", last_batch_id).pluck(:pull_request_id)
        end

        pull_request_ids
      end

      def issue_ids_for_repository(repository)
        issue_ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = repository.issues.without_pull_requests.limit(100_000).order(:id)
        batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id)

        while batch_ids.any?
          issue_ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id)
        end

        issue_ids
      end

      def all_issue_ids_for_repository(repository)
        issue_ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = repository.issues.limit(100_000).order(:id)
        batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id)

        while batch_ids.any?
          issue_ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id)
        end

        issue_ids
      end
    end
  end
end
