# frozen_string_literal: true

FactoryBot.define do
  factory :vulnerability do
    advisory

    package_ecosystem { generate(:ecosystem) }
    package_name
    vulnerable_version_range { generate(:version_range) }
    affected_functions { [] }

    trait :withdrawn do
      withdrawn_at { 1.second.ago }
    end

    before(:create) do |vulnerability|
      vulnerability.index ||= vulnerability.advisory.vulnerabilities.count

      # This might change in the future, but for now, vulnerabilities will only
      # inherit the severity of their parent advisories.
      vulnerability.severity ||= vulnerability.advisory.severity
    end
  end
end
