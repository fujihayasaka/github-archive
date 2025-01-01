# typed: true
# frozen_string_literal: true

require "test_helper"

class CompanyTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @existing_company = create(:company, name: "existing company")
  end

  context "validations" do
    test "require that company name is present" do
      company = build :company, name: ""
      refute_predicate company, :valid?
      assert_includes company.errors[:name], "can't be blank"
    end

    test "require that company name is the correct length" do
      company = build :company, name: "e" * 2000
      refute_predicate company, :valid?
      assert_includes company.errors[:name], "is too long (maximum is 1024 characters)"
    end
  end

  context "::valid_name?" do
    test "returns true if a Company with the same name already exists" do
      assert Company.find_by(name: "existing company")
      assert Company.valid_name?("existing company")
    end

    test "returns true if the name contains emoji" do
      assert Company.valid_name?("valid name 🌈")
    end

    test "returns false if the name is blank" do
      refute Company.valid_name?("")
    end

    test "returns false if the name is too long" do
      refute Company.valid_name?("e" * 2000)
    end
  end

  context "#name" do
    test "ensures UTF-8 encoding" do
      name = "日本語".b
      company = create(:company, name: name)
      assert_equal Encoding::UTF_8, company.name.encoding
    end

    test "supports emoji for name" do
      company = create(:company, name: "we ❤️ emojis")
      assert_multibyte_tracked_changes(company, :name)
    end
  end
end
