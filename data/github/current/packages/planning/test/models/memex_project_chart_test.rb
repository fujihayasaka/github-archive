# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectChartTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @user = create(:verified_user).tap { |u| @org.add_member(u) }
    @other_user = create(:verified_user).tap { |u| @org.add_member(u) }
    GitHub.flipper[:memex_insights].disable
    GitHub.flipper[:memex_charts_basic_allow].disable
  end

  context "validations" do
    test "requires a project" do
      chart = build(:memex_project_chart, memex_project: nil)

      refute chart.save
      assert_includes chart.errors.full_messages, "Memex project can't be blank"
    end

    test "requires a number" do
      chart = build(:memex_project_chart, number: nil)
      chart.stubs(:set_number) # Make the default setter a no-op.

      refute chart.save
      assert_includes chart.errors.full_messages, "Number can't be blank"
    end

    test "requires that number is a positive integer" do
      chart = build(:memex_project_chart, number: -1)

      refute chart.save
      assert_includes chart.errors.full_messages, "Number must be greater than 0"

      chart.number = 0.5
      refute chart.save
      assert_includes chart.errors.full_messages, "Number must be an integer"
    end

    test "requires that number is unique per project" do
      existing_chart = create(:memex_project_chart)
      new_chart = build(
        :memex_project_chart,
        memex_project: existing_chart.memex_project,
        number: existing_chart.number
      )

      refute new_chart.save
      assert_includes new_chart.errors.full_messages, "Number has already been taken"
    end

    test "sets a number by default" do
      chart = build(:memex_project_chart, number: nil)
      chart.save!

      refute_nil chart.reload.number
    end

    test "requires a creator" do
      chart = build(:memex_project_chart, creator: nil)

      refute chart.save
      assert_includes chart.errors.full_messages, "Creator can't be blank"
    end

    test "requires a name" do
      chart = build(:memex_project_chart, name: nil)
      chart.stubs(:set_name) # Make the default setter a no-op.

      refute chart.save
      assert_includes chart.errors.full_messages, "Name can't be blank"
    end

    test "requires that name cannot exceed a certain bytesize" do
      chart = build(:memex_project_chart, name: "x" * (MemexProjectChart::NAME_CHARACTER_LIMIT + 1))

      refute chart.save
      assert_includes chart.errors.full_messages, "Name is too long (maximum is 63 characters)"
    end

    test "allows emoji in the name" do

      chart = build(:memex_project_chart, name: "🏅")
      assert chart.save
      assert_equal "🏅", chart.reload.name
    end

    test "requires a configuration" do
      chart = build(:memex_project_chart, configuration: nil)

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration can't be blank"
    end

    test "requires private projects of free plans (user or org) to limit the number of charts created" do
      [:organization, :verified_user].each do |owner_type|
        free_owner = create(owner_type, plan: "free")
        private_project = create(:memex_project, owner: free_owner, public: false)

        assert_equal 2, MemexProjectChart::LIMITED_CHARTS_LIMIT
        MemexProjectChart::LIMITED_CHARTS_LIMIT.times do
          chart = build(:memex_project_chart, memex_project: private_project)
          assert chart.save
        end

        chart_over_limit = build(:memex_project_chart, memex_project: private_project)
        refute chart_over_limit.save
        assert_includes chart_over_limit.errors.full_messages, "This project is limited to 2 custom charts."

        # A third chart can be saved if the project is made public
        private_project.update(public: true)
        chart_over_limit = build(:memex_project_chart, memex_project: private_project)
        assert chart_over_limit.save
      end
    end

    [:memex_insights, :memex_charts_basic_allow].each do |feature_flag|
      test "does not require private projects of free plans (user or org) to limit the number of charts created if #{feature_flag} enabled" do
        GitHub.flipper[feature_flag].enable
        [:organization, :verified_user].each do |owner_type|
          free_owner = create(owner_type, plan: "free")
          private_project = create(:memex_project, owner: free_owner, public: false)

          assert_equal 2, MemexProjectChart::LIMITED_CHARTS_LIMIT
          MemexProjectChart::LIMITED_CHARTS_LIMIT.times do
            chart = build(:memex_project_chart, memex_project: private_project)
            assert chart.save
          end

          # with feature_flag enabled, a third chart can be saved
          chart_over_limit = build(:memex_project_chart, memex_project: private_project)
          assert chart_over_limit.save
        end
      end
    end

    test "does not require private projects of paid org plans to limit the number of charts created" do
      %w[business business_plus].each do |paid_plan|
        paid_org = create(:organization, plan: paid_plan)
        private_project = create(:memex_project, owner: paid_org, public: false)

        assert_equal 2, MemexProjectChart::LIMITED_CHARTS_LIMIT
        (MemexProjectChart::LIMITED_CHARTS_LIMIT + 1).times do
          chart = build(:memex_project_chart, memex_project: private_project)
          assert chart.save
        end
      end
    end

    test "enterprise plans have unlimited charts available", enterprise_only: true do
      paid_org = create(:organization, plan: "enterprise")
      private_project = create(:memex_project, owner: paid_org, public: false)

      assert_equal 2, MemexProjectChart::LIMITED_CHARTS_LIMIT
      (MemexProjectChart::LIMITED_CHARTS_LIMIT + 1).times do
        chart = build(:memex_project_chart, memex_project: private_project)
        chart.configuration["xAxis"]["dataSource"]["column"] = "time"
        assert chart.save
      end
    end

    test "does not require private projects of paid user plans to limit the number of charts created" do
      paid_user = create(:verified_user, plan: "pro")
      private_project = create(:memex_project, owner: paid_user, public: false)

      assert_equal 2, MemexProjectChart::LIMITED_CHARTS_LIMIT
      (MemexProjectChart::LIMITED_CHARTS_LIMIT + 1).times do
        chart = build(:memex_project_chart, memex_project: private_project)
        assert chart.save
      end
    end

    test "requires that configuration cannot exceed a certain bytesize as json" do
      chart = build(:memex_project_chart, configuration: "x" * (4096 + 1))

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration must be fewer than 4096 bytes as JSON"
    end

    test "requires configuration to contain 'filter'" do
      chart = build(:memex_project_chart)
      chart.configuration.delete("filter")

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'filter' must be present"
    end

    test "requires filter to be a string" do
      chart = build(:memex_project_chart)
      chart.configuration["filter"] = 1

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'filter' must be a string"
    end

    test "requires filter to be fewer than 256 characters" do
      chart = build(:memex_project_chart)
      chart.configuration["filter"] = "a" * (MemexProjectView::FILTER_CHARACTERS_LIMIT + 1)

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'filter' length must be fewer than 256 characters"
    end

    test "allows an empty 'filter' string" do
      chart = build(:memex_project_chart)
      chart.configuration["filter"] = ""
      assert chart.valid?
    end

    test "requires configuration to contain 'type'" do
      chart = build(:memex_project_chart)
      chart.configuration.delete("type")

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'type' must be present"
    end

    test "requires type to be one of a valid list" do
      chart = build(:memex_project_chart)
      chart.configuration["type"] = "invalid"

      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'type' must be one of: #{MemexProjectChart::CHART_TYPES.join(", ")}"
      )
    end

    test "allows chart configurations with valid types" do
      MemexProjectChart::CHART_TYPES.each do |type|
        chart = build(:memex_project_chart)
        chart.configuration["type"] = type
        assert chart.valid?
      end
    end

    test "requires configuration to contain an 'xAxis' hash" do
      chart = build(:memex_project_chart)
      chart.configuration.delete("xAxis")

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'xAxis' must be present"

      chart.configuration["xAxis"] = 1
      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'xAxis' must be a hash"
    end

    test "requires xAxis to contain a 'dataSource' hash" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"].delete("dataSource")

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'xAxis.dataSource' must be present"

      chart.configuration["xAxis"]["dataSource"] = 1
      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'xAxis.dataSource' must be a hash"
    end

    test "requires xAxis.dataSource to contain a valid 'column'" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"]["dataSource"].delete("column")
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'xAxis.dataSource.column' must be 'time' or an integer"
      )

      chart.configuration["xAxis"]["dataSource"]["column"] = "invalid"
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'xAxis.dataSource.column' must be 'time' or an integer"
      )

      [10, "time"].each do |column|
        chart.configuration["xAxis"]["dataSource"]["column"] = column
        assert chart.valid?
      end
    end

    test "allows xAxis.dataSource to contain a valid 'sortOrder'" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"]["dataSource"].delete("sortOrder")
      assert chart.valid?

      chart.configuration["xAxis"]["dataSource"]["sortOrder"] = "invalid"
      refute chart.valid?
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'xAxis.dataSource.sortOrder' must be one of: asc, desc"
      )

      MemexProjectChart::SORT_ORDERS.each do |sort_order|
        chart.configuration["xAxis"]["dataSource"]["sortOrder"] = sort_order
        assert chart.valid?
      end
    end

    test "requires xAxis.groupBy to be a hash, if present" do
      chart = build(:memex_project_chart)

      chart.configuration["xAxis"].delete("groupBy")
      assert chart.valid?

      chart.configuration["xAxis"]["groupBy"] = 1
      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'xAxis.groupBy' must be a hash"
    end

    test "requires xAxis.groupBy.column to be an integer" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"]["groupBy"] = {}
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'xAxis.groupBy.column' must be an integer"
      )

      chart.configuration["xAxis"]["groupBy"]["column"] = "invalid"
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'xAxis.groupBy.column' must be an integer"
      )

      chart.configuration["xAxis"]["groupBy"]["column"] = 9
      assert chart.valid?
    end

    test "allows xAxis.groupBy to contain a valid 'sortOrder'" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"]["groupBy"] = { "column" => 2 }
      assert chart.valid?

      chart.configuration["xAxis"]["groupBy"]["sortOrder"] = "invalid"
      refute chart.valid?
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'xAxis.groupBy.sortOrder' must be one of: asc, desc"
      )

      MemexProjectChart::SORT_ORDERS.each do |sort_order|
        chart.configuration["xAxis"]["groupBy"]["sortOrder"] = sort_order
        assert chart.valid?
      end
    end

    test "requires configuration to contain a 'yAxis' hash" do
      chart = build(:memex_project_chart)
      chart.configuration.delete("yAxis")

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'yAxis' must be present"

      chart.configuration["yAxis"] = 1
      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'yAxis' must be a hash"
    end

    test "requires yAxis to contain an 'aggregate' hash" do
      chart = build(:memex_project_chart)
      chart.configuration["yAxis"].delete("aggregate")

      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'yAxis.aggregate' must be present"

      chart.configuration["yAxis"]["aggregate"] = 1
      refute chart.save
      assert_includes chart.errors.full_messages, "Configuration 'yAxis.aggregate' must be a hash"
    end

    test "requires yAxis.aggregate to contain a valid 'operation'" do
      chart = build(:memex_project_chart)

      chart.configuration["yAxis"]["aggregate"].delete("operation")
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'yAxis.aggregate.operation' must be one of: count, sum, avg, min, max"
      )

      chart.configuration["yAxis"]["aggregate"]["operation"] = "invalid"
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'yAxis.aggregate.operation' must be one of: count, sum, avg, min, max"
      )

      MemexProjectChart::OPERATIONS.each do |operation|
        chart.configuration["yAxis"]["aggregate"]["operation"] = operation
        assert chart.valid?
      end
    end

    test "requires yAxis.aggregate.columns, if present, to be an array of integers" do
      chart = build(:memex_project_chart)

      chart.configuration["yAxis"]["aggregate"].delete("columns")
      assert chart.valid?

      chart.configuration["yAxis"]["aggregate"]["columns"] = "invalid"
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'yAxis.aggregate.columns' must be an array"
      )

      chart.configuration["yAxis"]["aggregate"]["columns"] = ["invalid"]
      refute chart.save
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'yAxis.aggregate.columns' must be an array of integers"
      )

      chart.configuration["yAxis"]["aggregate"]["columns"] = [1, 2, 3]
      assert chart.valid?
    end

    test "allows yAxis.aggregate to contain a valid 'sortOrder'" do
      chart = build(:memex_project_chart)
      chart.configuration["yAxis"]["aggregate"].delete("sortOrder")
      assert chart.valid?

      chart.configuration["yAxis"]["aggregate"]["sortOrder"] = "invalid"
      refute chart.valid?
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'yAxis.aggregate.sortOrder' must be one of: asc, desc"
      )

      MemexProjectChart::SORT_ORDERS.each do |sort_order|
        chart.configuration["yAxis"]["aggregate"]["sortOrder"] = sort_order
        assert chart.valid?
      end
    end

    test "ignores 'time' fields if 'xAxis.dataSource.column' is not time" do
      chart = build(:memex_project_chart)
      refute_equal chart.configuration["xAxis"]["dataSource"]["column"], "time"
      chart.configuration["time"] = { "period": "custom", "startDate": "2022-01-01", "endDate": "2022-01-02" }
      assert chart.configuration.has_key?("time")
      assert chart.valid?
      refute chart.configuration.has_key?("time")
    end

    test "defaults 'time.period' to '2W' if blank and 'xAxis.dataSource.column' is 'time'" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"]["dataSource"]["column"] = "time"
      refute chart.configuration.has_key?("time")
      assert chart.valid?
      assert_equal chart.configuration["time"]["period"], "2W"
    end

    test "requires 'time.period', if present, to be a valid period" do
      chart = build(:memex_project_chart)
      chart.configuration["xAxis"]["dataSource"]["column"] = "time"
      chart.configuration["time"] = { "period" => "invalid" }
      refute chart.valid?
      assert_includes(
        chart.errors.full_messages,
        "Configuration 'time.period' must be one of: 2W, 1M, 3M, max, custom"
      )
      MemexProjectChart::TIME_PERIODS.each do |period|
        chart.configuration["time"] = { "period" => period }
        assert chart.valid? unless period == "custom"
      end
      chart.configuration["time"] = {
        "period" => "custom",
        "startDate" => "2022-01-01",
        "endDate" => "2022-01-02",
      }
      assert chart.valid?
    end

    test "requires valid start and end dates if 'time.period' is 'custom'" do
      %w[startDate endDate].each do |date_type|
        chart = build(:memex_project_chart, :custom_time)
        assert chart.valid?
        chart.configuration["time"].delete(date_type)
        refute chart.valid?
        assert_includes(
          chart.errors.full_messages,
          "Configuration 'time.#{date_type}' must be in the format YYYY-MM-DD"
        )
        chart.configuration["time"][date_type] = "2/2/25" # invalid format
        refute chart.valid?
        assert_includes(
          chart.errors.full_messages,
          "Configuration 'time.#{date_type}' must be in the format YYYY-MM-DD"
        )
        chart.configuration["time"][date_type] = "2022-02-02" # valid format
        assert chart.valid?
      end
    end
  end

  context "#to_hash" do
    test "it returns a hash" do
      chart = create(:memex_project_chart)
      assert_equal(
        {
          name: chart.name,
          number: chart.number,
          configuration: chart.configuration,
        },
        chart.to_hash
      )
    end

    test "it omits nil values" do
      chart = build(:memex_project_chart)
      assert_equal(
        {
          configuration: chart.configuration,
        },
        chart.to_hash
      )
    end

    test "it uses a unique sequence scoped to the memex project for numbering" do
      chart = create(:memex_project_chart)
      assert_equal chart.memex_project.charts.count, 1
      assert_equal chart.number, 1
      initial_view_count = chart.memex_project.memex_project_views.count
      create(:memex_project_view, memex_project: chart.memex_project)
      assert_equal chart.memex_project.memex_project_views.count, initial_view_count + 1
      create(:memex_project_workflow, memex_project: chart.memex_project)
      assert_equal chart.memex_project.workflows.count, 1
      new_chart = create(:memex_project_chart, memex_project: chart.memex_project)
      assert_equal new_chart.number, 2
    end

    test "it uses a unique chart sequence per memex_project" do
      memex_project_1 = create(:memex_project)
      memex_project_2 = create(:memex_project)
      refute_equal memex_project_1.id, memex_project_2.id

      chart_1 = create(:memex_project_chart, memex_project: memex_project_1)
      chart_2 = create(:memex_project_chart, memex_project: memex_project_2)

      assert_equal chart_1.number, 1
      assert_equal chart_2.number, 1
    end
  end

  context "Project Chart instrumentation" do
    test "instruments project chart creation" do
      GitHub.context.push(actor_id: @user.id)
      project = create(:memex_project, creator: @user, owner: @org)

      reset_hydro

      chart = create(:memex_project_chart, memex_project: project, creator: @user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(chart.creator),
        project_chart: Hydro::EntitySerializer.memex_project_chart(chart),
        project: Hydro::EntitySerializer.memex_project(project)
      }, schema: "github.memex.v0.MemexProjectChartCreate")
    end

    test "instruments project chart update" do
      GitHub.context.push(actor_id: @other_user.id)
      project = create(:memex_project, creator: @user, owner: @org)
      chart = create(:memex_project_chart, memex_project: project, creator: @other_user)
      reset_hydro

      chart.update!(name: "New name")

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@other_user),
        project_chart: Hydro::EntitySerializer.memex_project_chart(chart),
        project: Hydro::EntitySerializer.memex_project(project)
      }, schema: "github.memex.v0.MemexProjectChartUpdate")
    end

    test "instruments project chart deletion" do
      GitHub.context.push(actor_id: @other_user.id)
      project = create(:memex_project, creator: @user, owner: @org)
      chart = create(:memex_project_chart, memex_project: project, creator: @other_user)

      assert chart.destroy
      assert chart.destroyed?

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@other_user),
        project_chart: Hydro::EntitySerializer.memex_project_chart(chart),
        project: Hydro::EntitySerializer.memex_project(project)
      }, schema: "github.memex.v0.MemexProjectChartDestroy")
    end
  end
end
