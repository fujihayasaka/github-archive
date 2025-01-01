# typed: true
# frozen_string_literal: true

require "test_helper"

class UserEducationDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#developer_pack_application_metadata" do
    test "returns the user's developer pack application metadata records" do
      application_metadata = create_list(:education_developer_pack_application_metadata, 2, :expired, user: @user)
      application_metadata << create(:education_developer_pack_application_metadata, :approved, user: @user)

      assert_same_elements application_metadata, @user.developer_pack_application_metadata
    end

    test "returns an empty scope of developer pack application metadata records if the user has none" do
      assert_empty @user.developer_pack_application_metadata
      assert_kind_of ActiveRecord::Relation, @user.developer_pack_application_metadata
    end
  end

  context "#education?" do
    context "when the user has an education email address" do
      test "returns true with an edu email" do
        user = create(:user, email: "github@harvard.edu")

        assert user.education?
      end

      test "returns true with an ac.uk email" do
        user = create(:user, email: "github@ox.ac.uk")

        assert user.education?
      end
    end

    context "when the user does not have an education email address" do
      test "returns false" do
        user = create(:user, email: "foo@github.com")

        refute user.education?
      end
    end

    context "when the user does not have an education coupon" do
      test "returns false" do
        refute @user.education?
      end
    end

    context "when the user has a student coupon" do
      test "returns true" do
        student_developer_pack_coupon = build(:coupon, :student_developer_pack)

        @user.coupons.push student_developer_pack_coupon

        assert @user.education?
      end
    end

    context "when the user has a teacher coupon" do
      test "returns true" do
        faculty_developer_pack_coupon = build(:coupon, :faculty_developer_pack)

        @user.coupons.push faculty_developer_pack_coupon

        assert @user.education?
      end
    end

    context "when the user has a classroom coupon" do
      test "detect education coupon codes" do
        classroom_coupon = build(:coupon, :classroom_coupon)

        @user.coupons.push classroom_coupon

        assert @user.education?
      end
    end
  end

  test "detects student developer pack coupon" do
    student_developer_pack_coupon = build(:coupon, :student_developer_pack)

    @user.coupons.push student_developer_pack_coupon

    assert @user.student_developer_pack_coupon?
  end

  test "detects faculty developer pack coupon" do
    faculty_developer_pack_coupon = build(:coupon, :faculty_developer_pack)

    @user.coupons.push faculty_developer_pack_coupon

    assert @user.faculty_developer_pack_coupon?
  end

  test "detects no student developer pack coupon" do
    invalid_coupon = build(
      :coupon,
      code: "not-students-dev-pack",
      discount: 0.5,
      group: "education-individual",
      duration: 29970,
    )

    @user.coupons.push invalid_coupon

    assert @user.has_an_active_coupon?
    refute @user.student_developer_pack_coupon?
  end
end
