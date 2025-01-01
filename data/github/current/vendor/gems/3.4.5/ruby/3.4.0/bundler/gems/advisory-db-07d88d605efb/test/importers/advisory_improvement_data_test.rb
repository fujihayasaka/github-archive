# frozen_string_literal: true

require "test_helper"

class AdvisoryImprovementDataTest < ActiveSupport::TestCase
  test "constructs advisory_payload from OSV using interface" do
    osv_data = {
      "schema_version" => "1.2.0",
      "id" => "GHSA-gppj-95f3-vh28",
      "modified" => "2022-02-10T02:31:56Z",
      "published" => "2022-02-10T02:31:55Z",
      "aliases" => ["CVE-2022-0001"],
      "summary" => "Dolores hic excepturi odio sint sed dignissimos et magni officia suscipit sit earum id",
      "details" => "Et sint qui. Tempore ut porro. Doloremque ratione cum.\n\nVel assumenda ut. Rem corporis nostrum. Est adipisci illo.\n\nExplicabo autem mollitia. Sit consequuntur et. Accusamus vero ipsum.\n\nVoluptatum assumenda rem. Id accusantium est. Quia maxime minus.\n\nFacere beatae laborum. Sunt et laudantium. Fuga dolore impedit.\n\nLibero omnis labore. Consequuntur ut error. Atque ut expedita.\n\nRerum doloremque excepturi. Eius suscipit molestiae. Consequatur provident mollitia.\n\nPerspiciatis nostrum ex. Officiis pariatur omnis. Quos et dignissimos.\n\nNihil quasi accusantium. Voluptas natus et. Voluptatem consequuntur maiores.\n\nMagni velit ea. Non ea voluptatum. Ea ratione ipsum.",
      "severity" => [
        { "type" => "CVSS_V3", "score" => "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:N/I:H/A:H" },
        { "type" => "CVSS_V4", "score" => "CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:L/VI:H/VA:L/SC:L/SI:H/SA:L" },
      ],
      "affected" => [
        {
          "package" => { "ecosystem" => "Maven", "name" => "EmeraldDiesel" },
          "ranges" => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0.1.4" }] }],
          "database_specific" => { "last_known_affected_version_range" => "< 0.2.3" },
        },
      ],
      "references" => [{ "type" => "WEB", "url" => "http://breitenberg.co/dian" }],
      "database_specific" => { "cwe_ids" => [], "severity" => "HIGH", "github_reviewed" => true },
    }

    improvement_data = AdvisoryImprovementData.create_from_improve_advisory_pr_json(
      pr_number: 1,
      json: osv_data,
      actor_login: "monalisa",
      actor_id: 1,
    )

    assert_equal osv_data["summary"], improvement_data.advisory_payload[:summary]
    assert_equal osv_data["details"], improvement_data.advisory_payload[:description]
    assert_equal ["http://breitenberg.co/dian"], improvement_data.advisory_payload[:references]
    assert_equal "maven", improvement_data.advisory_payload[:vulnerabilities][0][:ecosystem]
    assert_equal "EmeraldDiesel", improvement_data.advisory_payload[:vulnerabilities][0][:package_name]
    assert_equal ">= 0.1.4, < 0.2.3", improvement_data.advisory_payload[:vulnerabilities][0][:vulnerable_version_range]
    assert_equal "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:N/I:H/A:H", improvement_data.advisory_payload[:cvss_v3]
    assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:L/VI:H/VA:L/SC:L/SI:H/SA:L", improvement_data.advisory_payload[:cvss_v4]
  end

  test "can calculate a diff from an existing advisory review payload" do
    ref_1, ref_2 = generate_list(:url, 2)
    advisory_review = create(:advisory_review,
      advisory_payload: build(:advisory_payload,
        summary: "Magnam quo porro quisquam consequatur animi optio id ad sapiente omnis qui ut dolores amet",
        references: [ref_1]))
    improvement_data = build(:advisory_improvement_data,
      summary: "Magnam quo porro quisquam consequatur animi optio id ad sapiente omnis qui ut dolores amet",
      references: [ref_2])

    changes = improvement_data.advisory_payload_changes(advisory_review: advisory_review)
    refute changes.key?(:summary)
    assert_equal changes[:references], [[ref_1], [ref_2]]
  end

  test "calculates a diff in the severity, preferring CVSS 4, when both CVSS 3 and 4 vector strings are present" do
    advisory_review = create(:advisory_review, :with_cvss_v3) # Has "moderate" severity
    improvement_data = build(:advisory_improvement_data,
      cvss_v4: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H") # Has "high" severity
    changes = improvement_data.advisory_payload_changes(advisory_review: advisory_review)

    assert_equal ["moderate", "high"], changes[:severity]
  end
end
