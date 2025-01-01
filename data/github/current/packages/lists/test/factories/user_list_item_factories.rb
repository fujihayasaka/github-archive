# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :user_list_item do
    user_list { create(:user_list) }
    repository { create(:repository) }
  end
end
