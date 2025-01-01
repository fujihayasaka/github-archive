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

        issue = repo.issues.create(
          user: actor,
          title: "demo issue fields",
          body: Faker::Lorem.paragraph,
        )

        puts "Seeding issue fields..."

        create_text_field_with_value(
          org,
          actor,
          issue,
          "DRI",
          "Direct responsible individual",
          "@labudis"
        )

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

        create_text_field_with_value(
          org,
          actor,
          issue,
          "Eng Staffing",
          "Engineering staffing for this issue",
          "@iulia-b")

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

        create_single_select_field_with_value(
          org,
          actor,
          issue,
          "Priority",
          "The priority of this issue",
          [
            { name: "P0", color: :red },
            { name: "P1", color: :orange },
            { name: "P2", color: :yellow },
            { name: "P3", color: :pink },
            { name: "P4", color: :green },
          ]
        )
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
