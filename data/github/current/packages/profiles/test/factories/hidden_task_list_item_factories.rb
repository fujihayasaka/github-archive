# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :hidden_task_list_item do
    user
  end
end
