# typed: true
# frozen_string_literal: true

require "test_helper"

class LicenseTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "semour"
    @owner.create_profile name: "Semour Butts", email: "semour@example.com"
    @repo = create :repository, owner: @owner, description: "fancy description", name: "Fancy"
  end

  test "loading all licenses" do
    assert License.all.size > 3, "expected more licenses"
  end

  test "excludes hidden licenses by default" do
    assert License.all.none? { |l| l.hidden? }
  end

  test "includes hidden licenses when asked" do
    assert License.all(hidden: true).any? { |l| l.hidden? }
  end

  test "only returns featured licenses when asked" do
    assert License.all(featured: true).all? { |l| l.featured? }
  end

  test "only returns non-featured licenses when asked" do
    assert License.all(featured: false).none? { |l| l.featured? }
  end

  test "loading sorted license list" do
    last_featured_index = T.let(0, Integer)
    first_unfeatured_index = T.let(-1, Integer)
    License.sorted_list.each_with_index do |license, i|
      last_featured_index = i if license.featured?
      first_unfeatured_index = i unless license.featured? || first_unfeatured_index >= 0
    end
    assert last_featured_index == first_unfeatured_index - 1,
      "Unfeatured license(s) appeared before last featured license."
  end

  test "finding license by key" do
    license = License["mit"]
    assert_equal "MIT License", license.name
    assert_equal "mit", license.key
    assert_equal 13, license.id
  end

  test "finding licenses by ID" do
    license = License.find_by_id(13)
    assert_equal "MIT License", license.name
    assert_equal "mit", license.key

    # Got 99 licenses but this ain't one
    license = License.find_by_id(99)
    assert_nil license
  end

  test "loading license body" do
    license = License["mit"]
    assert_includes license.body, "Permission is hereby granted, free of charge, to any person"
  end

  test "featured licenses" do
    assert License["mit"].featured?
    assert !License["bsd-2-clause"].featured?
  end

  test "generating license files" do
    data = License["mit"].generate(repository: @repo)
    assert_includes data, "Copyright (c) #{Time.now.year} #{@owner.profile.name}"
  end

  # Make sure all licenses generate without error
  License.sorted_list.each do |license|
    test "generating the #{license.key} license" do
      data = license.generate(repository: @repo)
      assert data.is_a?(String)
      assert data.length > 0
    end
  end

  test "IDs are in sync with licenses" do
    github_licenses   = License::LICENSES_TO_IDS
    licensee_licenses = Licensee.licenses(hidden: true)

    # GitHub has IDs for all vendored licenses
    licensee_licenses.each do |license|
      msg = "The #{license.name} license has no numeric key. Please add one to app/models/license.rb."
      assert github_licenses.has_key?(license.key), msg
    end

    # No IDs exist for non-vendored licenses
    github_licenses.each_key do |key|
      assert Licensee::License.keys.include?(key), "The #{key} license is not vendored by Licensee"
    end

    # Number of licenses match vendored license count
    assert_equal github_licenses.count, licensee_licenses.count
  end

  test "knows known unknowns" do
    assert License.find_by_key "other", hidden: true
    assert_equal "other", License.find_by_id(0).key
    assert_equal "NOASSERTION", License.find_by_id(0).spdx_id
    assert_equal "Other", License.find_by_id(0).name
  end

  test "knows which licenses are hidden" do
    assert License.find_by_key("other", hidden: true).hidden?
    refute License.find_by_key("mit").hidden?
  end

  test "excludes hidden licenses from sorted license list" do
    refute License.sorted_list.any? { |l| l.name == "other" }
    refute License.sorted_list.any? { |l| l.hidden? }
  end

  test "#fields" do
    license = License["mit"]
    assert_equal license.fields.map(&:key), %w[year fullname]
    license = License["other"]
    assert_equal license.fields, []
  end

  test "#field_values_for_repository" do
    license = License.all.first

    value_hash = {
      "description" => "fancy description",
      "email"       => "semour@example.com",
      "fullname"    => "Semour Butts",
      "login"       => "semour",
      "project"     => "Fancy",
      "year"        => Time.now.year,
    }

    assert_equal license.field_values_for_repository(@repo), value_hash
  end
end
