# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsCriterionTest < GitHub::TestCase
  setup do
    skip unless GitHub.sponsors_enabled?
  end

  fixtures do
    @criterion = create(:sponsors_criterion)
  end

  context "validations" do
    test "creates a new criterion" do
      criterion = SponsorsCriterion.new(
        slug: "likes_pizza",
        description: "Account likes pizza?",
      )

      assert_predicate criterion, :valid?
      assert_predicate criterion, :checkbox?
    end

    test "creates a new criterion that has a text answer" do
      criterion = SponsorsCriterion.new(
        slug: "favorite_pizza_topping",
        description: "Enter this applicant's favorite pizza topping",
        criterion_type: :text,
      )

      assert_predicate criterion, :valid?
      assert_predicate criterion, :text?
    end

    test "requires a unique slug" do
      criterion = SponsorsCriterion.new(
        slug: @criterion.slug,
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug has already been taken", criterion.errors.full_messages.to_sentence
    end

    test "slug in different case of existing slug is not allowed" do
      criterion = SponsorsCriterion.new(
        slug: @criterion.slug.upcase,
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug has already been taken", criterion.errors.full_messages.to_sentence
    end

    test "slug with spaces is not allowed" do
      criterion = SponsorsCriterion.new(
        slug: "this is a test",
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug is invalid", criterion.errors.full_messages.to_sentence
    end

    test "slug with hyphens is not allowed" do
      criterion = SponsorsCriterion.new(
        slug: "random-test",
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug is invalid", criterion.errors.full_messages.to_sentence
    end

    test "slug beginning with underscore is not allowed" do
      criterion = SponsorsCriterion.new(
        slug: "_account_age",
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug is invalid", criterion.errors.full_messages.to_sentence
    end

    test "slug ending with underscore is not allowed" do
      criterion = SponsorsCriterion.new(
        slug: "account_age_",
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug is invalid", criterion.errors.full_messages.to_sentence
    end

    test "slug can't be over 60 characters" do
      slug = "a" * 61

      criterion = SponsorsCriterion.new(
        slug: slug,
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug is too long (maximum is 60 characters)", criterion.errors.full_messages.to_sentence
    end

    test "slug must be at least 3 characters" do
      criterion = SponsorsCriterion.new(
        slug: "hi",
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert_equal "Slug is too short (minimum is 3 characters)", criterion.errors.full_messages.to_sentence
    end

    test "slug must not contain emoji" do
      criterion = SponsorsCriterion.new(
        slug: "🐹",
        description: "Account is older than 6 months?",
      )

      refute_predicate criterion, :valid?
      assert criterion.errors[:slug].any?
    end

    test "requires a description" do
      criterion = SponsorsCriterion.new(
        slug: "cool_item",
        description: "",
      )

      refute_predicate criterion, :valid?
      assert_equal "Description can't be blank", criterion.errors.full_messages.to_sentence
    end
  end

  context "destroy" do
    test "destroys associated sponsors memberships criteria" do
      listing = create(:sponsors_listing)
      criterion = create(:sponsors_criterion)
      membership_criterion = create(:sponsors_memberships_criterion,
        sponsors_criterion: criterion, sponsors_listing: listing)

      assert_difference "SponsorsMembershipsCriterion.count", -1 do
        criterion.destroy
      end

      assert_nil SponsorsMembershipsCriterion.find_by(id: membership_criterion.id)
    end
  end

  context ".for" do
    test "returns criterion applicable to all and users for user sponsorable" do
      SponsorsCriterion.delete_all
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)

      assert_equal [all_criterion, user_criterion], SponsorsCriterion.for(create(:user))
    end

    test "returns criterion applicable to all and orgs for org sponsorable" do
      SponsorsCriterion.delete_all
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)

      assert_equal [all_criterion, org_criterion], SponsorsCriterion.for(create(:organization))
    end

    test "returns criterion applicable to all and orgs and fiscally hosted orgs org sponsorable" do
      SponsorsCriterion.delete_all
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)
      using_fiscal_host_criterion = create(:sponsors_criterion, applicable_to: :using_supported_fiscal_host)

      org = create(:sponsors_listing, :for_org, :with_fiscal_host).sponsorable
      assert_equal [all_criterion, org_criterion, using_fiscal_host_criterion], SponsorsCriterion.for(org)
    end

    test "returns empty relation for nil sponsorable" do
      SponsorsCriterion.delete_all
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)

      assert_empty SponsorsCriterion.for(nil)
    end

    test "returns only criterion that are active" do
      SponsorsCriterion.delete_all
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      inactive_criterion = create(:sponsors_criterion, applicable_to: :all, active: false)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)

      assert_equal [all_criterion, user_criterion], SponsorsCriterion.for(create(:user))
    end
  end
end
