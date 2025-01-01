# typed: true
# frozen_string_literal: true
require "test_helper"

class ProjectMigrationDependencyTest < GitHub::TestCase
  context "#to_memex_specification" do
    test "returns valid data representing basic project structure" do
      org_project = create(:org_project, name: "Triage board", body: "Our team triage board.", public: false)
      org_project.apply_template(ProjectTemplate::BugTriage.new)

      # Make sure that there are columns to migrate.
      assert_equal(
        ["Needs triage", "High priority", "Low priority", "Closed"],
        org_project.columns.map(&:name)
      )

      spec = org_project.to_memex_specification

      # Make sure the spec actually attempts to represent the basic project structure.
      refute_nil spec[:title]
      refute_nil spec[:description]
      assert_equal false, spec[:public]
      assert_includes spec[:views].first[:visible_fields], "Labels"
      refute_empty spec.dig(:status_field, :settings, :options)
      refute_empty spec[:views]
      refute_empty spec[:permissions]

      # Make sure the entire spec is valid.
      assert_nothing_raised { MemexProject::Migrator::Specification.new(spec).validate! }
    end

    test "returns valid data representing workflows" do
      org_project = create(:org_project, name: "Review Board", body: "Our team review board.", public: false)
      org_project.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
      refute_empty org_project.project_workflows

      spec = org_project.to_memex_specification

      refute_empty spec[:workflows]
      assert_nothing_raised { MemexProject::Migrator::Specification.new(spec).validate! }
    end

    test "queries replicas only" do
      org_project = create(:org_project, name: "Review Board", body: "Our team review board.", public: false)
      org_project.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)

      assert_all_queries_against_replicas do
        org_project.to_memex_specification
      end
    end

    test "prefills cards" do
      org_project = create(:org_project)
      repo = create(:repository, owner: org_project.organization)
      pr = create(:pull_request, :disable_disk_access, repository: repo)
      create(:project_card,
        project: org_project,
        content: create(:issue, repository: repo)
      )
      create(:project_card,
        project: org_project,
        content: create(:issue, repository: repo)
      )
      basecard = create(:project_card,
        project: org_project,
        content: pr
      )
      # Creating a card with nil priority will cause an issue with
      # the Ruby sort_by method, since comparison of nil with an integer
      # will raise an error. Any acrhived_cards will contain nil priority.
      nilcard = create(:archived_project_card,
        project: org_project,
        content: create(:issue, repository: repo)
      )

      # In order to verify the nil comparison error, we need to update the
      # nilcard's column_id to match the basecard's column_id so that there
      # is a comparison to be made.
      nilcard.update!(column_id: basecard.column_id)

      assert_equal 4, org_project.cards.size

      expected_queries = {
        issues: 1,
        project_cards: 1,
        project_columns: 1,
        pull_requests: 1
      }
      assert_max_query_count_per_table(expected_queries) do
        org_project.to_memex_specification
      end
    end

    test "prefills cards updated since a given time" do
      org_project = create(:org_project)

      Timecop.freeze 3.years.ago do
        create(:project_card,
          project: org_project,
          note: "3 year old card"
        )
      end

      Timecop.freeze 2.years.ago do
        create(:project_card,
          project: org_project,
          note: "2 year old card"
        )
      end

      Timecop.freeze 6.months.ago do
        create(:project_card,
          project: org_project,
          note: "6 month old card"
        )
      end

      Timecop.freeze 1.month.ago do
        create(:project_card,
          project: org_project,
          note: "1 month old card"
        )
      end

      assert_equal 4, org_project.cards.size

      expected_queries = {
        issues: 1,
        project_cards: 1,
        project_columns: 1,
        pull_requests: 1
      }
      spec = assert_max_query_count_per_table(expected_queries) do
        org_project.to_memex_specification(card_cutoff_date: 1.year.ago)
      end

      assert_equal 2, spec[:items].length
    end
  end
end
