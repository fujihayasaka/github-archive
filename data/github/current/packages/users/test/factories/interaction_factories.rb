# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :interaction do
    user
    active_sessions { 1 }
    last_active_session_at { 5.days.ago }
  end
end
