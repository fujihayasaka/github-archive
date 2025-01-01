# typed: true
# frozen_string_literal: true

require "thor"

module GlobalIdMigration
  class CLI < Thor
    package_name "global_id_migration"

    # https://github.com/erikhuda/thor/issues/244
    def self.exit_on_failure?
      true
    end

    desc "generate_usage_sql", "Generate the query to be pasted into data.githubapp.com to get usage stats for GraphQL objects."
    def generate_usage_sql
      GlobalIdMigration::DataDotQueryGenerator.run(node_implementors)
    end

    desc "schedule", "Report showing the details of the object rollout schedule"
    def schedule
      GlobalIdMigration::ResultPrinter.print(
        GlobalIdMigration::Schedule.run(build_details),
        formatter: formatter(:md)
      )
    end

    desc "objects", "Generate a list of Platform Objects"
    method_option :top, required: false, type: :numeric, default: 20, desc: "Number of objects to retrieve"
    method_option :most_used, required: false, type: :boolean, desc: "Get list of most used"
    method_option :least_used, required: false, type: :boolean, desc: "Get list of least used, that actually have _some_ usage."
    method_option :unused, required: false, type: :boolean, desc: "Get list of all unused objects."

    def objects
      if options[:most_used] && options[:least_used]
        raise "You must only provide either --most_used or --least_used, not both"
      end
      details = build_details

      if options[:most_used]
        results = details
          .sort_by { |_pon, deets| deets["usage_count"] }.reverse
      elsif options[:least_used]
        results = details
          .delete_if { |_pon, deets| deets["usage_count"] == 0 }
          .sort_by { |_pon, deets| deets["usage_count"] }
      elsif options[:unused]
        results = details
          .select { |_pon, deets| deets["usage_count"] == 0 }
      else
        results = details
      end

      GlobalIdMigration::ResultPrinter.print(results.take(options[:top].to_i))
    end

    desc "sample_code", "Show details for a given object"
    def sample_code(object_type)
      object = build_details[object_type]
      unless object
        puts "object not found in the migration artifacts."
        return
      end

      case object["ready_date"]
      when Platform::Helpers::GlobalId::COHORT_1
        object["ready_date"] = "Platform::Helpers::GlobalId::COHORT_1"
      when Platform::Helpers::GlobalId::COHORT_2
        object["ready_date"] = "Platform::Helpers::GlobalId::COHORT_2"
      when Platform::Helpers::GlobalId::COHORT_3
        object["ready_date"] = "Platform::Helpers::GlobalId::COHORT_3"
      when Platform::Helpers::GlobalId::COHORT_4
        object["ready_date"] = "Platform::Helpers::GlobalId::COHORT_4"
      when Platform::Helpers::GlobalId::COHORT_5
        object["ready_date"] = "Platform::Helpers::GlobalId::COHORT_5"
      else
        object["ready_date"] = "\"#{object["ready_date"]}\""
      end

      GlobalIdMigration::ResultPrinter.print(object, formatter: GlobalIdMigration::Formatting::Code)
    end

    desc "ready", "Objects already marked as ready"
    method_option :format, required: false, default: :json, desc: "Format for output [json|md]"

    def ready
      format = formatter(options[:format])
      raise "Invalid format provided" unless format
      details = build_details.select { |_pon, deets| deets["ready_date"] }.sort_by { |_pon, deets| deets["ready_date"] }
      report = {}
      report["headers"] = ["Object", "Ready Date"]
      report["rows"] = details.map { |k, v| [k, v["ready_date"]] }
      GlobalIdMigration::ResultPrinter.print(report, formatter: format)
    end

    private

    def build_details
      @build_details ||= GlobalIdMigration::Metadata.build(node_implementors)
    end

    def node_implementors
      return @node_implementors if defined?(@node_implementors)

      node_interface = ::Platform::Schema.get_type("Node")
      @node_implementors ||= ::Platform::Schema.possible_types(node_interface)
        .sort_by { |x| x.graphql_name }
        .delete_if { |x| !x.visibility.include?(:public) }
    end

    def formatter(format)
      {
        json: GlobalIdMigration::Formatting::Json,
        md: GlobalIdMigration::Formatting::Markdown,
      }[format.to_sym]
    end
  end
end
