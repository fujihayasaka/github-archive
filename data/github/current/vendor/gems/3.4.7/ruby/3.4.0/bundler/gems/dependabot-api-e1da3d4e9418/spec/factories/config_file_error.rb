# frozen_string_literal: true

FactoryBot.define do
  factory :config_file_error do
    association :repo
    error_details { { "message" => "My message" } }
    error_type { "unparseable_config_file" }
  end
end
