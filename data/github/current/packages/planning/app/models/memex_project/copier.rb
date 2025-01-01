# typed: true
# frozen_string_literal: true

class MemexProject
  # Public: Responsible for creating a new project based on:
  #   * `base_project`: The source project where we're coping from
  #   * `target_project`: The newly created project which is where we're copying information to
  #   * `include_draft_issues`: Copies draft issues from the base project if true
  class Copier
    extend T::Sig

    # How many items can be updated synchronously before we switch to enqueuing an asynchronous background job
    # Ideally this number would be lower, but more investment in UI exprience is desired prior
    # to enabling this more more projects
    ASYNC_DRAFTS_CUTOFF = 25

    # Total number of items that can be copied
    MAX_DRAFT_COPY_COUNT = 500
    # If true, we will skip various validations in memex models which are cumbersome when adding/updating items in bulk.
    @@copying = T.let(false, T::Boolean)

    # Enables "bulk mode" within the given block of code, which disables a variety of validations for Memex models
    sig { params(blk: T.proc.void).void }
    def self.with_copying(&blk)
      begin
        @@copying = true
        yield
      ensure
        @@copying = false
      end
    end

    # Returns whether or not we are currently copying items in bulk
    sig { returns(T::Boolean) }
    def self.copying?
      @@copying
    end

    def self.get_max_copy_count
      MAX_DRAFT_COPY_COUNT
    end

    sig { params(base_project: MemexProject, include_draft_issues: T::Boolean, is_template: T::Boolean, actor: User).returns(T.nilable(String)) }
    def self.get_max_draft_error(base_project:, include_draft_issues:, is_template:, actor:)
      return unless include_draft_issues
      show_error = base_project.memex_project_items.is_draft.not_archived.count > MAX_DRAFT_COPY_COUNT
      return nil unless show_error
      is_template ? "Unable to use template with more than #{MAX_DRAFT_COPY_COUNT} draft issues." : "Unable to copy project with more than #{MAX_DRAFT_COPY_COUNT} draft issues."
    end

    def initialize(base_project:, target_project:, include_draft_issues: false, actor:)
      @base_project = base_project
      @target_project = target_project
      @include_draft_issues = include_draft_issues
      @actor = actor
    end

    # Public: Create a copy of a project
    #
    # Returns MemexProject
    def execute
      copier_result_args = { target_project: @target_project }

      Copier.with_copying do
        start_time = GitHub::Dogstats.monotonic_time
        tags = ["include_draft_issues:#{@include_draft_issues}"]

        # Serialize the project
        project_template = MemexProject::StructureSerializer.new(@base_project).serialize

        # Apply the template to the base/default project
        @target_project.apply_template(creator: @target_project.creator, template: project_template)
        # when copying to an org, set the creator as the project admin
        grant_admin_role(@target_project) if @target_project.owner.is_a?(Organization)

        # copy draft items
        if @include_draft_issues
          drafts = @base_project
            .memex_project_items
            .is_draft
            .not_archived
            .includes(:memex_project_column_values)
            # Preloading the content to prevent N+1 queries
            .includes(:content)
            # Forcing a load of the drafts here so that `drafts.any?` below doesn't trigger an extra query
            .to_a

          tags << "height:#{MemexPerformanceStatsHelper.height_bucket(drafts.count)}"

          if drafts.count > ASYNC_DRAFTS_CUTOFF
            MemexProjectCopyDraftIssuesJob.perform_later(
              actor_id: @actor.id,
              source_memex_project_id: @base_project.id,
              target_memex_project_id: @target_project.id,
            )

            copier_result_args[:copying_drafts_async] = true
          elsif drafts.any?
            draft_issue_copy_builder = DraftIssueCopyBuilder.new(source_project: @base_project, target_project: @target_project)
            drafts.each do |source_draft_issue_item|
              draft_issue_copy_builder.build_draft_issue_copy(source_draft_issue_item)
            end

            # Ignore updating `updated_at` fields since we are creating new records anyway
            MemexProject.no_touching do
              MemexProjectItem.no_touching do
                @target_project.save
              end
            end
            @target_project.rebalance(association: :memex_project_items)
          end
        end

        GitHub.dogstats.distribution(
          "memex.copier.execute",
          GitHub::Dogstats.duration(start_time),
          tags: tags,
        )
      end

      CopierResult.new(**copier_result_args)
    end

    def grant_admin_role(project)
      project.grant_role(project.creator, :admin)
    rescue Permissions::Granters::RoleGranter::GrantFailure
      project.destroy!
    end

    class DraftIssueCopyBuilder
      extend T::Sig

      sig { params(source_project: MemexProject, target_project: MemexProject).void }
      def initialize(source_project:, target_project:)
        @source_project = source_project
        @target_project = target_project

        # We include all user-defined columns and the status column (all others either cannot have values for draft
        # issues or are explicitly set in the build_draft_issue call below)
        @source_columns = @source_project.memex_project_columns.reject do |column|
          column.system_defined? && !column.status?
        end

        # get the new project's columns
        @target_columns_lookup = @target_project.memex_project_columns.index_by(&:name)
      end

      # Creates a copy of a draft issue item in a target project, but does not persist it.
      sig { params(source_draft_issue_item: MemexProjectItem).returns(MemexProjectItem) }
      def build_draft_issue_copy(source_draft_issue_item)
        target_draft_issue_item = @target_project.build_draft_issue(
          creator: T.must(@target_project.creator),
          title: source_draft_issue_item.content.title,
          assignees: [],
          body: source_draft_issue_item.content.body,
          build_denormalized_values: true
        )
        draft_issue_column_values = source_draft_issue_item.memex_project_column_values.index_by(&:memex_project_column_id)

        # Set custom fields on the draft issue
        @source_columns.each do |source_column|
          target_project_column = @target_columns_lookup[source_column.name]
          next unless target_project_column

          source_column_value = draft_issue_column_values[source_column.id]&.value
          next unless source_column_value.present?

          # build a value object
          column_value = target_draft_issue_item.memex_project_column_values.build(
            memex_project_column: target_project_column,
            creator: @target_project.creator
          )

          # set the value but do not save; saving the project will cascade
          column_value.value = source_column_value
        end

        target_draft_issue_item
      end
    end

    class CopierResult
      extend T::Sig

      sig { returns(::MemexProject) }
      attr_reader :target_project

      sig { params(target_project: ::MemexProject, copying_drafts_async: T::Boolean).void }
      def initialize(target_project:, copying_drafts_async: false)
        @target_project = target_project
        @copying_drafts_async = copying_drafts_async
      end

      sig { returns(T::Boolean) }
      def copying_drafts_async?
        @copying_drafts_async
      end

      sig { returns(T.nilable(String)) }
      def get_async_copying_message
        return nil unless @copying_drafts_async
        "Copying draft issues to your new project. This may take a minute to complete."
      end
    end

    class DraftIssueCopyNotifier
      extend T::Sig

      sig { params(target_project: MemexProject, actor: User, success: T::Boolean).void }
      def initialize(target_project:, actor:, success:)
        @target_project = target_project
        @actor = actor
        @success = success
      end

      sig { void }
      def notify_memex_channel
        # Keep in sync with `isValidBulkCopyEventShape()` in ui/packages/memex/src/client/helpers/alive.ts
        # See also allowed fields in SocketMessageData in ui/packages/memex/src/client/api/SocketMessage/contracts.ts
        data = {
          bulkCopySuccess: @success,
          actor: { id: @actor.id },
        }

        @target_project.notify_memex_channel(data)
      end
    end
  end
end
