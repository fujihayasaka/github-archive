# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :bulk_sponsorship_import do
    transient do
      sponsorables { [create(:user, :sponsorable)] }
    end

    sponsor { create(:user) }
    data do
      sponsorables.map do |sponsorable|
        { "sponsorable_login" => sponsorable.login, "amount" => 5 }
      end
    end
  end
end
