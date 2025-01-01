# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_memberships_criterion do
    sponsors_criterion
  end
end
