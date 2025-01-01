# typed: true
# frozen_string_literal: true

module GlobalIdMigration
  class Metadata
    def self.build(node_implementors)
      usage     = JSON.parse(File.read("lib/global_id_migration/artifacts/global_id_usage.json"))
      templates = JSON.parse(File.read("lib/global_id_migration/artifacts/global_id_templates.json"))

      # ignore any platform objects in the template report that have been
      # removed from the schema.
      templates.delete_if { |o, _d| !node_implementors.map(&:to_s).include?(o) }

      # ignore any non-public platform object
      templates.delete_if { |o, _d| !o.constantize.visibility.include?(:public) }

      # blow up if there are new objects not in our templates file
      if (missing = node_implementors.map(&:to_s) - templates.keys).any?
        raise "there are new Platform Objects that haven't been added to the migration plan. #{missing.inspect}"
      end

      templates.each do |object_type, details|
        usage_details = usage.detect { |u| u["object_type"] == object_type.split("::").last }
        details["object_type"] = object_type
        details.merge!(usage_details) if usage_details
      end

      templates.map do |platform_type_name, details|
        if platform_type_name.end_with?("AuditEntry")
          details["ready_date"] = "2021-09-01"
        end

        object = platform_type_name.constantize

        details["ready_date"] ||= (object.global_id_ready_date&.strftime("%Y-%m-%d") || details["suggested_ready_date"] || "TBD")

        details["status"] = if object.global_id_templates && object.global_id_ready_date
          if object.global_id_ready_date <= DateTime.now
            "Rolled Out"
          else
            "Implemented"
          end
        else
          "TODO"
        end
      end

      templates
    end
  end
end
