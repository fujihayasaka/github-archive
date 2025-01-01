# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CustomPropertiesForOrgs < Seeds::Runner
      ENTERPRISE_NAME = "OrgPropsInc".freeze
      ORG_NAMES = %w[acme-corp tech-solutions innovate-labs digital-dynamics future-systems].freeze

      def self.help
        <<~HELP
        Create some organization custom properties. And set some values for them.
        HELP
      end

      def self.run(options = {})
        puts "Seeding custom properties for organizations 🌱"

        Seeds::Objects::FeatureFlag.enable(feature_flag: "custom_properties_for_orgs")
        Seeds::Objects::FeatureFlag.enable(feature_flag: "custom_enterprise_role_feature")
        Seeds::Objects::FeatureFlag.enable(feature_flag: "custom_properties_for_orgs_fgp")
        Seeds::Objects::FeatureFlag.enable(feature_flag: "custom_properties_shared_components")

        user = Seeds::Objects::User.monalisa

        business = Seeds::Objects::Business.create(owner: user, name: ENTERPRISE_NAME)

        puts "Created enterprise: #{business.name}"

        orgs = ORG_NAMES.map do |org_name|
          org = Seeds::Objects::Organization.create(login: org_name, admin: user)
          business.add_organization(org)

          puts "Created organization: #{org.display_login} in business: #{business.name}"
          org.reload
        end

        definitions = [
          {
            name: "service_tier",
            description: "Service tier classification for the organization",
            free_text_values: %w[enterprise standard basic],
            value_type: "string",
            set_on: %w[acme-corp tech-solutions]
          },
          {
            name: "infrastructure_stack",
            allowed_values: %w[kubernetes docker serverless microservices monolithic],
            description: "Infrastructure technology stack used by the organization",
            value_type: "single_select",
            set_on: %w[innovate-labs digital-dynamics future-systems]
          },
          {
            name: "data_storage",
            allowed_values: %w[postgresql mysql mongodb elasticsearch redis],
            description: "Primary data storage solutions utilized by the organization for managing and persisting application data",
            value_type: "single_select",
          },
          {
            name: "cloud_provider",
            description: "Cloud infrastructure provider for hosting services",
            free_text_values: %w[aws azure gcp hybrid on-premises],
            value_type: "string",
            set_on: %w[tech-solutions innovate-labs]
          },
          {
            name: "environment_tier",
            allowed_values: %w[production staging development sandbox],
            description: "Environment classification for deployment stages",
            value_type: "single_select",
            set_on: %w[digital-dynamics]
          },
          {
            name: "infrastructure_cluster",
            description: "Primary infrastructure cluster identifier",
            value_type: "string",
            required: true,
            default_value: "enterprise-main-cluster",
          },
          {
            name: "monitoring_enabled",
            value_type: "true_false",
            set_on: %w[tech-solutions]
          },
          {
            name: "enterprise_grade",
            description: "Whether the organization uses enterprise-grade solutions",
            value_type: "true_false",
            required: true,
            default_value: "false",
            set_on: %w[innovate-labs digital-dynamics]
          },
          {
            name: "organization_unit",
            free_text_values: %w[platform-engineering infrastructure-ops security-ops data-engineering devops-automation compliance enterprise-architecture],
            value_type: "string",
            set_on: %w[future-systems]
          },
          {
            name: "capacity_scale",
            description: "Organization capacity scaling units",
            allowed_values: (1..10).map { |i| "#{i} enterprise_unit#{i > 1 ? "s" : ""}" },
            value_type: "single_select",
            set_on: %w[acme-corp tech-solutions innovate-labs]
          },
          {
            name: "deployment_targets",
            description: "Target deployment environments and platforms",
            allowed_values: %w[multi-cloud hybrid-cloud edge-computing enterprise-datacenter],
            value_type: "multi_select",
            set_on: %w[digital-dynamics future-systems]
          },
          {
            name: "org_identifier",
            value_type: "string",
            regex: "[0-9]+",
            set_on: []
          },
        ]

        Orgs.domain.custom_properties.destroy_all_property_definitions(business)

        definitions.each do |definition|
          Orgs.domain.custom_properties.save_definition(
            business,
            property_name: definition[:name],
            value_type: definition[:value_type],
            allowed_values: definition[:allowed_values],
            required: definition[:required] || false,
            default_value: definition[:default_value],
            regex: definition[:regex],
            description: definition[:description],
          )
        end

        orgs.each { |org| set_properties(business, org, definitions) }

        puts "Successfully seeded custom properties for organizations 🚀"
      end

      def self.set_properties(business, target, definitions)
        properties = {}
        definitions.each do |definition|
          next unless definition[:set_on]&.include?(target.display_login)
          values = case definition[:value_type]
          when "string"
            definition[:free_text_values]&.sample || Faker::Lorem.word
          when "single_select"
            definition[:allowed_values]&.sample
          when "multi_select"
            definition[:allowed_values]&.sample(2) || []
          when "true_false"
            %w(true false).sample
          else
            raise ArgumentError, "Unknown value type: #{definition[:value_type]}"
          end

          properties[definition[:name]] = values
        end

        Orgs.domain.custom_properties.set_properties_for(business, [target], properties, actor: business.admins.first)
      end
    end
  end
end
