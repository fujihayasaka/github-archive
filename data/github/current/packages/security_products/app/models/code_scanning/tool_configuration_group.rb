# typed: strict
# frozen_string_literal: true

# A ToolConfigurationGroup represents a set of configurations that come from
# the same delivery origin and workflow file.
# From a UX perspective, this controls how configurations are grouped on the tool status page.

module CodeScanning
  class ToolConfigurationGroup
    include GitHub::Memoizer
    include ActionView::Helpers::UrlHelper
    include SecurityAnalysisSettingsHelper
    extend T::Sig

    sig do
      params(
        repository: Repository,
        configuration_group: Turboscan::Proto::ConfigurationGroup,
        categories: T::Array[Turboscan::Proto::CategoryStatus],
        overall_status: Integer,
        workflow: T.nilable(CodeScanning::Status::Workflow),
        tool_name: String,
      ).void
    end
    def initialize(repository:, configuration_group:, categories:, overall_status:, workflow:, tool_name:)
      @configuration_group = configuration_group
      @categories = categories
      @overall_status = overall_status
      @workflow = workflow
      @repository = repository
      @tool_name = tool_name
    end

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(Turboscan::Proto::ConfigurationGroup) }
    attr_reader :configuration_group

    sig { returns(T.any(Symbol, Integer)) }
    def delivery_origin
      configuration_group.delivery_origin
    end

    sig { returns(T::Array[Turboscan::Proto::CategoryStatus]) }
    attr_reader :categories

    sig { returns(Integer) }
    attr_reader :overall_status

    sig { returns(T.nilable(CodeScanning::Status::Workflow)) }
    attr_reader :workflow

    sig { returns(String) }
    def workflow_path
      configuration_group.workflow_path
    end

    sig { returns(String) }
    attr_reader :tool_name

    sig do
      params(
        repository: Repository,
        tool: Turboscan::Proto::ToolStatus,
        messages: CodeScanning::Status::Messages,
        workflows: T::Hash[String, CodeScanning::Status::Workflow],
      ).returns(T::Array[CodeScanning::ToolConfigurationGroup])
    end
    def self.build_groups(repository:, tool:, messages:, workflows:)
      grouped_categories = tool.categories.group_by(&:configuration_group)
      grouped_categories.filter_map do |configuration_group, categories|
        # T.unsafe because of splat: https://sorbet.org/docs/error-reference#7019
        overall_status = ::CodeScanning::Status.max_level(T.unsafe(messages).fetch(tool.name, *categories))

        next if configuration_group.nil?

        ::CodeScanning::ToolConfigurationGroup.new(
          repository: repository,
          configuration_group: configuration_group,
          categories: categories,
          overall_status: overall_status,
          workflow: workflows[configuration_group.workflow_path],
          tool_name: tool.name,
        )
      end
    end

    sig { params(configuration_group: Turboscan::Proto::ConfigurationGroup).returns(String) }
    def self.slug(configuration_group:)
      case configuration_group.delivery_origin
      when :DELIVERY_ORIGIN_YML then "actions-#{GitHub::Base32.encode(configuration_group.workflow_path)}"
      when :DELIVERY_ORIGIN_API then "api"
      when :DELIVERY_ORIGIN_DYNAMIC then "dynamic"
      when :DELIVERY_ORIGIN_MANAGED then "automatic"
      when :DELIVERY_ORIGIN_UNKNOWN then "artificial"
      else raise ArgumentError.new("Unknown delivery origin: #{configuration_group.delivery_origin}")
      end
    end

    sig { returns(String) }
    def setup_type
      ActionController::Base.helpers.strip_tags(setup_type_with_links)
    end

    sig { returns(String) }
    def setup_type_with_links
      case delivery_origin
      when :DELIVERY_ORIGIN_YML then "Actions workflow"
      when :DELIVERY_ORIGIN_API then "API upload"
      when :DELIVERY_ORIGIN_DYNAMIC then "Dynamic workflow"
      when :DELIVERY_ORIGIN_MANAGED then link_to("Default setup", security_analysis_settings_path(@repository))
      when :DELIVERY_ORIGIN_UNKNOWN then tool_name
      else raise ArgumentError.new("Unknown delivery origin: #{delivery_origin}")
      end
    end

    sig { returns(String) }
    def slug
      self.class.slug(configuration_group: @configuration_group)
    end

    sig { returns(T.nilable(String)) }
    memoize def name
      if delivery_origin == :DELIVERY_ORIGIN_YML
        unless @workflow.nil? || @workflow.name == @workflow.path
          return @workflow.name
        end
        workflow_path.delete_prefix(".github/workflows/")
      end
    end

    sig { returns(T::Boolean) }
    memoize def missing_workflow?
      delivery_origin == :DELIVERY_ORIGIN_YML && workflow.nil?
    end

    sig { returns(T.nilable(String)) }
    def description
      case delivery_origin
      when :DELIVERY_ORIGIN_YML then
        workflow_path.delete_prefix(".github/workflows/")
      end
    end

    sig { returns(T::Boolean) }
    def show_workflow?
      delivery_origin == :DELIVERY_ORIGIN_YML && (scan_events.present? || schedules.present?)
    end

    sig { returns(T.untyped) }
    memoize def schedules
      schedule_list = workflow&.schedule
      return nil if !schedule_list.is_a?(Array)
      schedule_list = schedule_list.select { |schedule| schedule.is_a?(Hash) }
      schedule_list = schedule_list.map { |schedule| schedule.fetch("cron", nil) }
      schedule_list = schedule_list.select { |schedule| schedule.is_a?(String) }
      return nil if schedule_list.empty?

      schedule_list
    end

    sig { returns(T.untyped) }
    memoize def scan_events
      if delivery_origin == :DELIVERY_ORIGIN_MANAGED
        protected_branch_names = @repository.protected_branches.pluck(:name)
        branches = [repository.default_branch, *protected_branch_names].uniq
        {
          "push" => { "branches" => branches },
          "pull_request" => { "branches" => branches },
        }
      else
        workflow&.events
      end
    end

    sig { returns(T.nilable(Time)) }
    def first_scan
      @categories.map { |category| category.created_at&.to_time }.min
    end

    sig { returns(T.nilable(Time)) }
    def last_scan
      @categories.map { |category| category.updated_at&.to_time }.max
    end
  end
end
