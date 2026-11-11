# frozen_string_literal: true

FactoryBot.define do
  factory :autofix_suggestion_job do
    association :pull_request
    target_sha { "1asdkjh123jk" }
    rule_sarif_identifier { "npm_autofix/v1" }
    check_run_id { Faker::Number.number(digits: 10) }

    trait :with_sarif do
      sarif_content do
        JSON.generate({
                        "runs" => [{
                          "results" => [{
                            "level" => "error",
                            "message" => {
                              "text" => "This JSX tag's 'children' prop expects type 'never' which requires multiple "\
                              "children, but only a single child was provided."\
                              "---Type 'string' is not assignable to type 'never'.",
                            },
                            "locations" => [{
                              "physicalLocation" => {
                                "artifactLocation" => { "uri" => "package.json" },
                                "region" => { "startLine" => 2, "startColumn" => 5, "endLine" => 3, "endColumn" => 10 },
                              },
                            }],
                          }],
                        }],
                      })
      end
    end

    trait :with_suggested_fix do
      association :suggested_fix
    end
  end
end
