# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class ExportCsvGenerator

      ELEMENT_COUNT_CAP = 20
      RepositoryRowResult = T.type_alias do
        T.any(
          SecurityCenter::Coverage::ExportDataQuery::RepositoryRowResult,
          SecurityOverviewAnalytics::Coverage::ExportQuery::ListItem,
        )
      end

      sig do
        params(
          query_results: T::Array[RepositoryRowResult],
          property_headers: T.nilable(T::Array[String]),
          write_headers: T::Boolean,
          owner: T.nilable(T.any(Organization, Business))
        ).returns(String)
      end
      def self.generate(query_results, property_headers:, write_headers: true, owner: nil)
        property_headers&.sort! # we rely on this being in a consistent order between setting headers and assigning values

        use_new_headers = self.use_new_headers?(owner)
        base_headers = if use_new_headers
          ["Owner", "Repository", "Owner type"]
        else
          %w[Organization Name]
        end

        headers = base_headers + [
          "Archived",
          "Updated At",
          "Visibility",
          "Dependabot Alerts Status",
          "Dependabot Security Updates Status",
          "Code Scanning Alerts Status",
          "Code Scanning Pull Request Alerts Status",
          "Code Scanning Default Setup Status",
          "Secret Scanning Alerts Status",
          "Secret Scanning Push Protection Status",
          "Advanced Security Status",
          "Topics",
          "Teams (truncated at #{ELEMENT_COUNT_CAP} values)"
        ]

        include_repo_properties = include_repo_properties?(owner)
        if include_repo_properties
          property_headers&.each do |property|
            headers << "Custom Property: #{property}"
          end
        end

        list_field_converter = proc do |value|
          if value.is_a?(Array)
            # Quote each value, comma separate them, wrap that in brackets, then quote the whole thing
            # "["apple","banana","pear"]"
            %{["#{value.join('","')}"]} if value.present?
          else
            value
          end
        end
        write_converters = [list_field_converter]

        CSV.generate(write_headers:, headers:, write_converters:) do |csv|
          query_results.each do |row|
            org, name = row.name_with_display_owner.split("/")
            payload = [
              org,
              name,
              row.archived,
              row.updated_at,
              row.visibility,
              row.dependabot_alerts_status,
              row.dependabot_security_updates_status,
              row.code_scanning_alerts_status,
              row.code_scanning_pull_request_alerts_status,
              row.code_scanning_default_setup,
              row.secret_scanning_alerts_status,
              row.secret_scanning_push_protection_status,
              row.advanced_security_status,
              row.topics.sort,
              row.teams.sort.first(ELEMENT_COUNT_CAP),
            ]
            payload.insert(2, row.owner_type) if use_new_headers

            if include_repo_properties && row.is_a?(SecurityOverviewAnalytics::Coverage::ExportQuery::ListItem)
              property_headers&.each do |property|
                property_values = row.repository_properties.with_indifferent_access[property]
                if property_values.is_a?(Array)
                  property_values = property_values.sort.first(ELEMENT_COUNT_CAP)
                end

                payload << property_values
              end
            end
            csv << payload
          end
        end
      end

      sig { params(owner: T.nilable(T.any(Organization, Business))).returns(T::Boolean) }
      def self.use_new_headers?(owner)
        return false if owner.nil?
        ::SecurityCenter::FeatureFlagHelper.enterprise_coverage_csv_export?(owner)
      end

      sig { params(owner: T.nilable(T.any(Organization, Business))).returns(T::Boolean) }
      def self.include_repo_properties?(owner)
        FeatureFlagHelper.coverage_export_include_repo_properties?(owner)
      end
    end
  end
end
