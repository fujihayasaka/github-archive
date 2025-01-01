# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module FineGrainedResources
      def fine_grained_resources_config
        config = {}
        config["business"] = {}
        config["organization"] = {}
        config["repository"] = {}
        config["user"] = {}
        config["workflow_run"] = {}
        config["protected_branch"] = {}
        config["pull_request"] = {}
        config["package_registry"] = {}
        config["codespace"] = {}

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/business")
                  .glob("**/*.yml")
                  .each { |c| config["business"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/organization")
                  .glob("**/*.yml")
                  .each { |c| config["organization"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/repository")
                  .glob("**/*.yml")
                  .each { |c| config["repository"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/user")
                  .glob("**/*.yml")
                  .each { |c| config["user"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/workflow_run")
                  .glob("**/*.yml")
                  .each { |c| config["workflow_run"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/protected_branch")
                  .glob("**/*.yml")
                  .each { |c| config["protected_branch"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/pull_request")
                  .glob("**/*.yml")
                  .each { |c| config["pull_request"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/package_registry")
                  .glob("**/*.yml")
                  .each { |c| config["package_registry"].merge!(YAML.safe_load c.read) }

        Rails.root.join("config/access_control/fine_grained_permissions/programmatic_actor_fine_grained_resources/codespace")
                  .glob("**/*.yml")
                  .each { |c| config["codespace"].merge!(YAML.safe_load c.read) }

        config
      end

      def fine_grained_resources
        @fine_grained_resources ||= fine_grained_resources_config
      end

      # There are a small number of resources that exist with the same name at different resource group
      # levels. These resources should all be private and this code will never be called for one of those
      # duplicate resources, if it is we will return the first match (the same behavior as before this change)
      def fine_grained_resource(resource)
        fine_grained_resources.each do |_, resources|
          return resources[resource] if resources.key?(resource)
        end

        nil
      end

      def public_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["visibility"] == "public" }.keys
      end

      def private_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["visibility"] == "private" }.keys
      end

      def preview_fine_grained_resources(resource_group)
        output_hash = fine_grained_resources[resource_group].each_with_object({}) do |(key, value), result|
          if value["visibility"] == "preview"
            result[key] = value["feature_flag"].to_sym
          end
        end
      end

      def enterprise_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["visibility"] == "ghes_only" }.keys
      end

      def emu_only_fine_grained_resources(resource_group)
        output_hash = fine_grained_resources[resource_group].each_with_object({}) do |(key, value), result|
          if value["visibility"] == "emu_only"
            result[key] = value["feature_flag"]&.to_sym
          end
        end
      end

      def writeonly_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["fgp"] == "write_only" }.keys
      end

      def readonly_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["fgp"] == "read_only" }.keys
      end

      def adminable_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["fgp"] == "adminable" }.keys
      end

      def connectonly_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["visibility"] == "connect_only" }.keys
      end

      def authzd_fine_grained_resources(resource_group)
        fine_grained_resources[resource_group].select { |_, v| v["authzd_enabled"] }.keys
      end

      def excluded_actors_fine_grained_resources(resource_group)
        fgps_with_exclusions = fine_grained_resources[resource_group].select { |_, v| v.key?("excluded_actors") }

        fgps_with_exclusions.each_with_object({}) do |(key, value), result|
          value["excluded_actors"].each do |excluded_actor|
            actor_class = Object.const_get(excluded_actor)
            result[actor_class] ||= []
            result[actor_class] << key
          end
        end
      end
    end
  end

  extend Config::FineGrainedResources
end
