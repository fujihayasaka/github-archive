# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingExternalEmailTest < GitHub::TestCase
  fixtures do
    @business = create(:business, billing_email: "billing@github.com")
  end

  if GitHub.billing_enabled?
    test "creates a billing external email" do
      billing_external_email = build(:billing_external_email, :business_owner)

      assert_difference "BillingExternalEmail.count", 1 do
        billing_external_email.save!
      end
    end

    test "creates multiple billing external emails for owner" do
      org = create(:organization)
      2.times.each do |i|
        create(:billing_external_email, :organization_owner, owner: org, email: "money-#{i}@example.com")
      end

      assert_equal 2, org.billing_external_emails.count
    end

    test "doesn't create billing external email if an owner's current billing email is already taken" do
      billing_external_email = build(:billing_external_email, :business_owner,
        owner: @business, email: "billing@github.com")

      assert_raises ActiveRecord::RecordInvalid do
        billing_external_email.save!
      end
    end

    test "doesn't create billing external email if an email format is incorrect" do
      billing_external_email = build(:billing_external_email, :business_owner, email: "invalid-email-string")

      assert_raises ActiveRecord::RecordInvalid do
        billing_external_email.save!
      end
    end

    test "doesn't create billing external email if an email is blank" do
      billing_external_email = build(:billing_external_email, :business_owner, email: "invalid-email-string")

      assert_raises ActiveRecord::RecordInvalid do
        billing_external_email.save!
      end
    end

    test "doesn't create billing external email if an email is nil" do
      billing_external_email = build(:billing_external_email, :business_owner, email: nil)

      assert_raises ActiveRecord::RecordInvalid do
        billing_external_email.save!
      end
    end
  end
end
