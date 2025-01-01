# typed: true
# frozen_string_literal: true

module GitHub
  module Importer2
    # Synopsis:
    #
    #     GitHub.importer.create_issue(ImportItem.find(1))
    #
    class IssueCreator
      def initialize(import_item)
        @import_item = import_item
      end

      attr_reader :import_item

      # Don't call this from a unicorn!
      def import!
        importing do
          if import_item.reload.status != "pending"
            GitHub.dogstats.increment "import_issue", tags: ["type:duplicate_job", "status:#{import_item.status}"]
            return
          end

          if issue = create_issue(import_item.data["issue"])
            Array(import_item.data["comments"]).each_with_index do |comment_data, i|
              create_comment(issue, comment_data, i)
            end

            # Set updated_at after creating comments because Comment#save touches the Issue.
            update_updated_at(issue, import_item.data["issue"])
          end

          import_item.data = nil if import_item.status == "imported"
          import_item.save!
        end
      rescue Freno::Throttler::CircuitOpen, Freno::Throttler::WaitedTooLong => error
        raise error
      rescue => e # rubocop:todo Lint/RescueException
        error_id = SecureRandom.hex(20)
        Failbot.report!(e, "gh.migration_tools.import_payload_error.id" => error_id)
        import_item.status = "failed"
        import_item.save!
        import_item.add_import_error \
          payload_location: "n/a",
          resource: "Internal Error",
          code: "error",
          value: error_id
      end

      private

      def importing
        # Be nice to mysql and its replicas.
        Issue.throttle do
          # Disable notifications and stratocaster.
          GitHub.importing do
            # Disable content creation rate limits, because
            # a) we're doing a large amount of work that's likely to run
            #    afoul of the limit.
            # b) this runs inside of a `throttle` block (in the job that
            #    calls this), so we're being polite to the database its replicas.
            # c) we've got notifications disabled, which should also reduce
            #    the impact of inserting new records.
            GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
              yield
            end
          end
        end
      end

      def create_issue(issue_data)
        create_issue_attributes = ::Issues::CreateIssueAttributes.new(
          title: issue_data["title"],
          repository: import_item.repository)

        user = import_item.user

        if user&.bot?
          # rehydrate intallation so user can be properly authorized
          user = IntegrationInstallation
            .with_repository(import_item.repository)
            .where(integration: user.integration).first&.bot
        end

        issue_actor = user
        create_issue_attributes.body = issue_data["body"]
        create_issue_attributes.created_at = issue_data["created_at"]

        if milestone_id = issue_data["milestone"]
          if milestone = import_item.repository.milestones.find_by_number(milestone_id.to_i)
            create_issue_attributes.milestone = milestone
          else
            import_item.add_import_error \
              payload_location: "/issue/milestone",
              resource: "Issue",
              field: "milestone",
              value: issue_data["milestone"],
              code: "invalid"
          end
        end

        if assignee_login = issue_data["assignee"]
          if user = User.find_by_login(assignee_login)
            create_issue_attributes.assignee = user
          else
            import_item.add_import_error \
              payload_location: "/issue/assignee",
              resource: "Issue",
              field: "assignee",
              value: issue_data["assignee"],
              code: "invalid"
          end
        end

        label_names = issue_data["labels"]
        if label_names.present?
          labels = []
          label_names.each_with_index do |label_name, index|
            label = import_item.repository.labels.where(name: label_name).first_or_initialize
            if label.valid?
              labels << label
            else
              import_item.add_import_error \
                payload_location: "/issue/labels[#{index}]",
                resource: "Label",
                field: "name",
                value: label_name,
                code: "invalid"
            end
          end
          create_issue_attributes.labels = labels
        end

        if issue_actor.nil?
          result = GH::Result::Error::NotFound.new
          import_item.add_import_error \
            payload_location: "/issue/user_id",
            resource: "Issue",
            field: "user_id",
            value: issue_actor,
            code: "invalid"
        elsif !import_item.import_errors.empty?
          result = GH::Result::Error.new
        else
          create_issue_attributes.labels&.each do |label|
            T.unsafe(label).save
          end
          result = ::Issues.domain.create(
            create_issue_attributes,
            issue_actor,
            skip_permission_checks: true,
            fail_on_invalid_assignees: true,
          )
        end

        issue = T.let(nil, T.nilable(::Issue))
        case result
        when GH::Result::Ok
          issue = T.must(T.cast(result.value, ::Issue))
          import_item.model_id = issue.id
        when GH::Result::Error::Validation
          result.model.errors.each do |error|
            field = error.attribute
            value = T.unsafe(result.model)[field] || issue_data[field.to_s]

            import_item.add_import_error \
                        payload_location: "/issue/#{field}",
            resource: "Issue",
            field: field,
            value: value.to_s,
            code: "invalid"
          end
        end

        if import_item.import_errors.empty? && result.ok? # domain-isolation-query-violation:ignore:packages/issues (INSERT, SELECT, UPDATE)
          issue = T.must(issue)
          import_item.model_id = issue.id
          issue.close if issue_data["closed"] # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)

          if issue_data["closed"] && issue_data["closed_at"]
            issue.update_attribute :closed_at, issue_data["closed_at"] # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
          end

          if issue_data["closed"] && issue_data["closed_at"]
            close_event = T.must(issue.events.closes.first)
            close_event.created_at = issue_data["closed_at"]
            close_event.save # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          import_item.status = "imported"
          issue
        else
          import_item.status = "failed"
          nil
        end
      rescue => e # rubocop:todo Lint/RescueException
        report_import_error e,
          payload_location: "/issue",
          resource: "Issue"
        nil
      end

      def update_updated_at(issue, issue_data)
        if issue_data["updated_at"]
          issue.update_attribute :updated_at, issue_data["updated_at"] # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
        end
      end

      def create_comment(issue, comment_data, index)
        comment = issue.comments.new
        comment.user = import_item.user
        comment.body = comment_data["body"]
        comment.created_at = comment_data["created_at"]
        comment.save!
      rescue => e # rubocop:todo Lint/RescueException
        report_import_error e,
          payload_location: "/comments[#{index}]",
          resource: "IssueComment"
        nil
      end

      def report_import_error(error, error_data)
        error_item = import_item.add_import_error(**{ code: "error" }.merge(error_data))
        Failbot.report!(error, "app" => "github-user", "gh.migration_tools.import_payload_error.id" => error_item.id)
        import_item.status = "failed"
      end
    end
  end
end
