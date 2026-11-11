# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class IssueFields < Seeds::Runner
      def self.help
        <<~HELP
        Create sample data for Issue Fields
        HELP
      end

      def self.run(options = {})
        require_relative "./check_run"

        prepare_options(options)

        if seed_number > 0
          puts "Using seed '#{seed_number}'"
          srand(seed_number)
        else
          seed = Random.new_seed
          puts "Assigning seed '#{seed}'"
          srand(seed)
        end

        execute(options)

        puts "Repairing Elastometer indexes..."
        Elastomer::App.run ["repair"]
      end

      def self.prepare_options(options)
        options = options.transform_keys(&:to_sym)

        seed = options[:seed] || 0

        @options = { seed: seed }
      end

      def self.seed_number
        @options[:seed] || 0
      end

      def self.execute(options = {})
        org = Seeds::Objects::Organization.github
        actor = Seeds::Objects::User.monalisa
        repo = Seeds::Objects::Repository.create(owner_name: org, setup_master: true, is_public: false, repo_name: "issue-fields")

        # Get or create the Task issue type first
        task_type = IssueType.where(owner: org, name: "Task").first_or_create!(color: "green", description: "Work item or task")

        issue = repo.issues.create(
          user: actor,
          title: "demo issue fields",
          body: Faker::Lorem.paragraph,
          issue_type: task_type,
        )

        puts "Seeding issue fields..."

        # Create fields for pinning (at least one of each supported type)
        text_field_dri = create_text_field(org, actor, "DRI", "Direct responsible individual")
        text_field_staffing = create_text_field(org, actor, "Eng Staffing", "Engineering staffing for this issue")
        date_field_start = create_date_field(org, actor, "Start date", "Date when work on issue will begin")
        date_field_target = create_date_field(org, actor, "Target date", "Expected completion date for this issue")
        number_field_story_points = create_number_field(org, actor, "Story Points", "Estimated effort in story points")
        priority_field = create_single_select_field(
          org,
          actor,
          "Priority",
          "Current importance level assigned to this issue",
          [
            { name: "Urgent", color: :pink, priority: 1 },
            { name: "High", color: :red, priority: 2 },
            { name: "Medium", color: :yellow, priority: 3 },
            { name: "Low", color: :green, priority: 4 },
          ]
        )
        stage_field = create_single_select_field(
          org,
          actor,
          "Stage",
          "The current stage of the issue",
          [
            { name: "Triage", color: :green, priority: 1 },
            { name: "Backlog", color: :gray, priority: 2 },
            { name: "In progress", color: :green, priority: 3 },
            { name: "Done", color: :purple, priority: 4 },
            { name: "Blocked", color: :yellow, priority: 5 },
          ]
        )

        # Setup pinned fields for issue types
        puts "Setting up pinned fields for issue types..."
        setup_pinned_fields(org, actor)

        # Set values on the demo issue
        create_text_field_value(issue, actor, text_field_dri, "@labudis")

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "Product pillar",
          "The product pillar this issue belongs to",
          [
            { name: "Core Productivity", color: :gray },
            { name: "Security Products", color: :gray },
            { name: "Platform & Enterprise", color: :gray },
            { name: "Copilot Productivity", color: :gray },
            { name: "Copilot Intelligence Platform", color: :gray },
            { name: "DevDiv", color: :gray },
            { name: "Models", color: :gray },
            { name: "Miscellaneous", color: :gray },
          ]
        )

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "Trending",
          "How is this issue trending?",
          [
            { name: "On track", color: :green },
            { name: "At risk", color: :yellow },
            { name: "Off track", color: :red },
            { name: "Inactive", color: :gray },
            { name: "Not planned", color: :gray },
            { name: "Done", color: :purple },
          ]
        )

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "Secondary Status",
          "The current status of the issue",
          [
            { name: "Triage", color: :green },
            { name: "Needs prioritization", color: :gray },
            { name: "Backlog", color: :gray },
            { name: "Shaping", color: :yellow },
            { name: "Ready for work", color: :blue },
            { name: "Next up", color: :blue },
            { name: "In progress", color: :green },
            { name: "Done", color: :purple },
            { name: "Blocked", color: :yellow },
            { name: "Paused", color: :orange },
            { name: "Stopped", color: :pink },
            { name: "Future", color: :blue },
          ]
        )

        create_text_field_with_value(
          org,
          actor,
          issue,
          "Last Report Date",
          "The date of the last report for this issue",
          "05/21/2025"
        )

        create_text_field_value(issue, actor, text_field_staffing, "@iulia-b")

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "Work Type",
          "The type of work this issue represents",
          [
            { name: "Availability", color: :blue },
            { name: "Copilot", color: :purple },
            { name: "Eng Efficiency", color: :orange },
            { name: "Features and Growth", color: :green },
            { name: "FR, on Call and KTLO", color: :yellow },
            { name: "Fundamentals and Fanout", color: :pink },
            { name: "Customer support", color: :green },
            { name: "Loan", color: :blue },
          ]
        )

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "EPD Strategy Type",
          "The type of EPD strategy this issue belongs to",
          [
            { name: "Core Productivity Strategy", color: :gray },
            { name: "Enterprise Strategy", color: :gray },
            { name: "Platform Strategy", color: :gray },
            { name: "Security Products Strategy", color: :gray },
            { name: "Design Strategy", color: :gray },
            { name: "DX Strategy", color: :gray },
          ]
        )

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "Deliverable",
          "The deliverable stage of this issue",
          [
            { name: "External Preview", color: :gray },
            { name: "External GA", color: :gray },
            { name: "Staffship/Internal Release", color: :gray },
            { name: "Internal Milestone", color: :gray },
            { name: "Private Preview", color: :gray },
            { name: "Public Preview", color: :gray },
            { name: "Post GA", color: :gray },
            { name: "GA", color: :gray },
            { name: "ESM+ERP Private Preview", color: :gray },
            { name: "ERP Public Preview", color: :gray },
          ]
        )
      end

      # Helper method to create a text field without setting a value
      # @param owner [Organization] The organization that owns the field
      # @param actor [User] The user creating the field
      # @param field_name [String] The name of the field
      # @param field_description [String] The description of the field
      # @return [IssueField] The created or existing field
      def self.create_text_field(owner, actor, field_name, field_description)
        field = IssueField.where(owner: owner, name: field_name).first
        if !field
          field = IssueField.create!(
            name: field_name,
            description: field_description,
            data_type: :text,
            owner: owner,
            actor: actor
          )
        end
        field
      end

      # Helper method to create a date field without setting a value
      # @param owner [Organization] The organization that owns the field
      # @param actor [User] The user creating the field
      # @param field_name [String] The name of the field
      # @param field_description [String] The description of the field
      # @return [IssueField] The created or existing field
      def self.create_date_field(owner, actor, field_name, field_description)
        field = IssueField.where(owner: owner, name: field_name).first
        if !field
          field = IssueField.create!(
            name: field_name,
            description: field_description,
            data_type: :date,
            owner: owner,
            actor: actor
          )
        end
        field
      end

      # Helper method to create a number field without setting a value
      # @param owner [Organization] The organization that owns the field
      # @param actor [User] The user creating the field
      # @param field_name [String] The name of the field
      # @param field_description [String] The description of the field
      # @return [IssueField] The created or existing field
      def self.create_number_field(owner, actor, field_name, field_description)
        field = IssueField.where(owner: owner, name: field_name).first
        if !field
          field = IssueField.create!(
            name: field_name,
            description: field_description,
            data_type: :number,
            owner: owner,
            actor: actor
          )
        end
        field
      end

      # Helper method to create a single select field with options
      # @param owner [Organization] The organization that owns the field
      # @param actor [User] The user creating the field
      # @param field_name [String] The name of the field
      # @param field_description [String] The description of the field
      # @param options [Array<Hash>] An array of options with name, color, and optional priority keys
      # @return [IssueField] The created or existing field
      def self.create_single_select_field(owner, actor, field_name, field_description, options)
        field = IssueField.where(owner: owner, name: field_name).first

        if !field
          field = IssueField.create!(
            name: field_name,
            description: field_description,
            data_type: :single_select,
            owner: owner,
            actor: actor
          )

          # Create all options
          options.each do |option|
            puts "creating an option for field #{field_name}: #{option[:name]}"
            IssueFieldOption.create!(
              issue_field: field,
              name: option[:name],
              color: option[:color],
              priority: option[:priority],
              owner: owner,
            )
          end
        end

        field
      end

      # Helper method to create a text field value on an issue
      # @param issue [Issue] The issue to set the field value on
      # @param actor [User] The user creating the value
      # @param field [IssueField] The field to set
      # @param text_value [String] The text value to set
      def self.create_text_field_value(issue, actor, field, text_value)
        value = IssueFieldValue.where(issue: issue, issue_field: field).first
        if !value
          IssueFieldValue.create!(
            issue_field: field,
            data_type: field.data_type,
            issue: issue,
            repository: issue.repository,
            value: text_value,
            actor: actor
          )
        end
      end

      # Setup pinned fields for issue types
      # @param org [Organization] The organization
      # @param actor [User] The user setting up the fields
      def self.setup_pinned_fields(org, actor)
        # Get or create default issue types
        bug_type = IssueType.where(owner: org, name: "Bug").first_or_create!(color: "red", description: "Something isn't working")
        feature_type = IssueType.where(owner: org, name: "Feature").first_or_create!(color: "purple", description: "New feature or request")
        task_type = IssueType.where(owner: org, name: "Task").first

        # Get the fields we created
        priority_field = IssueField.where(owner: org, name: "Priority").first
        stage_field = IssueField.where(owner: org, name: "Stage").first
        start_date_field = IssueField.where(owner: org, name: "Start date").first
        target_date_field = IssueField.where(owner: org, name: "Target date").first
        story_points_field = IssueField.where(owner: org, name: "Story Points").first

        # Pin fields to Bug type: Priority, Stage
        if bug_type && priority_field && stage_field
          result = ::Issues.domain.planning_templates.add_bulk_issue_type_fields_mapping(
            org: org,
            issue_type: bug_type,
            issue_fields: [priority_field, stage_field],
            positions: nil
          )
          puts "Pinned fields to Bug type: #{result.ok? ? 'success' : 'failed'}"
        end

        # Pin fields to Feature type: Priority, Stage, Target date
        if feature_type && priority_field && stage_field && target_date_field
          result = ::Issues.domain.planning_templates.add_bulk_issue_type_fields_mapping(
            org: org,
            issue_type: feature_type,
            issue_fields: [priority_field, stage_field, target_date_field],
            positions: nil
          )
          puts "Pinned fields to Feature type: #{result.ok? ? 'success' : 'failed'}"
        end

        # Pin fields to Task type: Priority, Stage, Start date, Target date, Story Points
        if task_type && priority_field && stage_field && start_date_field && target_date_field && story_points_field
          result = ::Issues.domain.planning_templates.add_bulk_issue_type_fields_mapping(
            org: org,
            issue_type: task_type,
            issue_fields: [priority_field, stage_field, start_date_field, target_date_field, story_points_field],
            positions: nil
          )
          puts "Pinned fields to Task type: #{result.ok? ? 'success' : 'failed'}"
        end

        # Pin fields to Organization (no type): Priority, Stage, Start date, Target date
        if priority_field && stage_field && start_date_field && target_date_field
          result = ::Issues.domain.planning_templates.set_pinned_issue_fields_for_no_type_issues(
            org: org,
            issue_fields: [priority_field, stage_field, start_date_field, target_date_field],
            positions: nil
          )
          puts "Pinned fields to Organization (no type): #{result.ok? ? 'success' : 'failed'}"
        end
      end

      # Helper method to create a single select field with options and set its value on an issue
      # @param owner [Organization] The organization that owns the field
      # @param actor [User] The user creating the field
      # @param issue [Issue] The issue to set the field value on
      # @param field_name [String] The name of the field
      # @param field_description [String] The description of the field
      # @param options [Array<Hash>] An array of options with name and color keys
      def self.create_single_select_field_with_value(owner, actor, issue, field_name, field_description, options)
        # Find or create the field
        field = IssueField.where(owner: owner, name: field_name).first

        if !field
          field = IssueField.create!(
            name: field_name,
            description: field_description,
            data_type: :single_select,
            owner: owner,
            actor: actor)

          # Create all options
          options.each do |option|
            puts "creating an option for field #{field_name}: #{option[:name]}"
            option_record = IssueFieldOption.create!(
              issue_field: field,
              name: option[:name],
              color: option[:color],
              owner: owner,
            )
          end
        end

        default_option = IssueFieldOption.where(issue_field: field).first

        # Create the value for the issue if it doesn't exist
        value = IssueFieldValue.where(issue: issue, issue_field: field).first
        if !value
          value = IssueFieldValue.create!(
            issue_field: field,
            data_type: field.data_type,
            issue: issue,
            repository: issue.repository,
            value: T.must(default_option).id,
            actor: actor
          )
        end
      end

      # Helper method to create a text field and set its value on an issue
      # @param owner [Organization] The organization that owns the field
      # @param actor [User] The user creating the field
      # @param issue [Issue] The issue to set the field value on
      # @param field_name [String] The name of the field
      # @param field_description [String] The description of the field
      # @param text_value [String] The text value to set on the issue
      def self.create_text_field_with_value(owner, actor, issue, field_name, field_description, text_value)
        # Find or create the field
        field = IssueField.where(owner: owner, name: field_name).first
        if !field
          field = IssueField.create!(
            name: field_name,
            description: field_description,
            data_type: :text,
            owner: owner,
            actor: actor)
        end

        # Create the value for the issue if it doesn't exist
        value = IssueFieldValue.where(issue: issue, issue_field: field).first
        if !value
          value = IssueFieldValue.create!(
            issue_field: field,
            data_type: field.data_type,
            issue: issue,
            repository: issue.repository,
            value: text_value,
            actor: actor
          )
        end
      end
    end
  end
end
