# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  # Used for testing with TEST_WITH_ALL_EMUS is set to true
  trait :enterprise_managed_profile do
    PROFILE_ATTRIBUTES_TO_REJECT = %i[id mail user_id created_at updated_at]

    initialize_with do
      if attributes[:user] && profile = User.find(attributes[:user].id).profile
        # All EMU users will already have a profile created for them
        # re-query it and set the attributes, otherwise do default save!
        attributes_to_update = attributes.reject { |k, _v| PROFILE_ATTRIBUTES_TO_REJECT.include?(k) }
        profile.assign_attributes(attributes_to_update)
        profile
      else
        new(attributes)
      end
    end
  end

  factory :profile, traits: TestEnv.test_with_all_emus? ? [:enterprise_managed_profile] : [] do
    user
    email { Sham.email }
  end
end
