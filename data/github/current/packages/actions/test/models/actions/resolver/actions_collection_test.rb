# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Resolver::V2::Internal::ActionsCollectionTest < GitHub::TestCase
  context "Identifies valid semver actions and normalises wildcards" do
    test "ALLOWED full semver (1.0.0)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.0.0")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.0.0", normalised_semver: "1.0.0"),
      ]
    end

    test "ALLOWED patch wildcard semver (1.0.x)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.0.x")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.0.x", normalised_semver: "1.0.*"),
      ]
    end

    test "ALLOWED patch wildcard semver (1.0.X) (uppercase X)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.0.X")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.0.X", normalised_semver: "1.0.*"),
      ]
    end

    test "ALLOWED minor wildcard semver (1.x)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.x")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.x", normalised_semver: "1.*"),
      ]
    end

    test "ALLOWED minor wildcard semver (1.X) (uppercase X)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.X")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.X", normalised_semver: "1.*"),
      ]
    end

    test "ALLOWED with prelease" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.3.2-prerelease")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.3.2-prerelease", normalised_semver: "1.3.2-prerelease"),
      ]
    end


    test "ALLOWED with build" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.3.2+meta")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.3.2+meta", normalised_semver: "1.3.2+meta"),
      ]
    end

    test "ALLOWED with prelease and build" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.3.2-prerelease+meta")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.3.2-prerelease+meta", normalised_semver: "1.3.2-prerelease+meta"),
      ]
    end

    test "ALLOWED with prelease containing dots" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.2.3-alpha.beta.4")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.2.3-alpha.beta.4", normalised_semver: "1.2.3-alpha.beta.4"),
      ]
    end

    test "ALLOWED with complex semver" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "1.2.3-alpha-a.b-c-somethinglong+build.1-aef.1-its-okay")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "1.2.3-alpha-a.b-c-somethinglong+build.1-aef.1-its-okay", normalised_semver: "1.2.3-alpha-a.b-c-somethinglong+build.1-aef.1-its-okay"),
      ]
    end

    test "DISALLOWED major wildcard semver (x)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "x")])

      assert_equal collection.unclassified_semver_actions, []

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", ref: "x")
      ]
    end
  end

  context "Normalises legacy semver actions" do
    test "ALLOWED @v1 -> @1.*" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "v1")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "v1", normalised_semver: "1.*"),
      ]
    end

    test "ALLOWED @v1 -> @1.*  (uppercase V)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "V1")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "V1", normalised_semver: "1.*"),
      ]
    end

    test "ALLOWED @v1.0 -> @1.0.*" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "v1.0")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "v1.0", normalised_semver: "1.0.*"),
      ]
    end

    test "ALLOWED @V1.0 -> @1.0.* (uppercase V)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "V1.0")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "V1.0", normalised_semver: "1.0.*"),
      ]
    end

    test "ALLOWED @v1.0.0 -> @1.0.0" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "v1.0.0")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "v1.0.0", normalised_semver: "1.0.0"),
      ]
    end


    test "ALLOWED @V1.0.0 -> @1.0.0 (uppercase V)" do
      collection = Actions::Resolver::V2::Internal::ActionsCollection.new([Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: "a/b",
        ref: "V1.0.0")])

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "V1.0.0", normalised_semver: "1.0.0"),
      ]
    end
  end

  context "Marking Actions" do
    test "Default classification" do
      input = [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", ref: "v3"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "1.0.0"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "g/h", ref: "1.0.x"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", ref: "main"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "k/l", ref: "master"),
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "a/b", ref: "v3", normalised_semver: "3.*"),
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "e/f", ref: "1.0.0", normalised_semver: "1.0.0"),
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "g/h", ref: "1.0.x", normalised_semver: "1.0.*"),
      ]

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", ref: "main"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "k/l", ref: "master"),
      ]

      # Semver actions are by default unclassified hence `package_actions` is empty.
      assert_equal collection.package_actions, []
    end

    test "Semver Actions can be marked as served by a repository ref or packages" do
      input = [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", ref: "v3"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "1.0.0"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "g/h", ref: "1.0.x"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", ref: "main"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "k/l", ref: "master"),
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      collection.serve_semver_from_repository_ref!(nwo: "e/f", ref: "1.0.0")
      collection.serve_semver_from_package_version!(nwo: "g/h", ref: "1.0.x",
        full_semver: "1.0.0",
        package_id: 20,
        package_visibility: :public)

      collection.impossible_to_serve!(nwo: "a/b", ref: "v3", error: :version_not_found)


      ## Repository Actions

      assert_equal collection.repository_actions, [
        # These are not semver so they are always served form a repository ref.
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", ref: "main"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "k/l", ref: "master"),

        # We marked this one
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "1.0.0")
      ]

      ## Packages Actions
      assert_equal collection.package_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::PackageAction.new(requested_nwo: "g/h", ref: "1.0.x",
          normalised_semver: "1.0.*",
          full_semver: "1.0.0",
          package_id: 20,
          package_visibility: :public),
      ]

      ## Unservable Actions
      assert_equal collection.unservable_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(
          requested_nwo: "a/b",
          ref: "v3",
          normalised_semver: "3.*",
          error: :version_not_found),
      ]
    end

    test "Semver Actions & Repository Actions can be marked as impossible to serve" do
      input = [
        # These will be auto-classified as repository actions
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", ref: "a72f4ef636fa9771fcc6fbb428fb07148f983d91"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "some-tag"),
        # These will be unclassified semver actions
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "g/h", ref: "1.0.x"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", ref: "1.0.0"),
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      # Assert the default classification
      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "g/h", ref: "1.0.x", normalised_semver: "1.0.*"),
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "i/j", ref: "1.0.0", normalised_semver: "1.0.0"),
      ]

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", ref: "a72f4ef636fa9771fcc6fbb428fb07148f983d91"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "some-tag"),
      ]

      # Mark some of them as impossible to serve
      collection.impossible_to_serve!(nwo: "a/b", ref: "a72f4ef636fa9771fcc6fbb428fb07148f983d91", error: :blocked_action)
      collection.impossible_to_serve!(nwo: "g/h", ref: "1.0.x", error: :version_not_found)

      # Assert the new classification
      assert_equal collection.unclassified_semver_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction.new(requested_nwo: "i/j", ref: "1.0.0", normalised_semver: "1.0.0"),
      ]

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "some-tag"),
      ]

      # Assert the impossible to serve actions
      assert_equal collection.unservable_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(
          requested_nwo: "a/b",
          ref: "a72f4ef636fa9771fcc6fbb428fb07148f983d91",
          normalised_semver: nil,
          error: :blocked_action),
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(
          requested_nwo: "g/h",
          ref: "1.0.x",
          normalised_semver: "1.0.*",
          error: :version_not_found),
      ]
    end

    test "Unclassified semver actions can be iterated over while the collection is being modified" do
      input = [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "actions/checkout", ref: "v4"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "actions/download-artifact", ref: "v4"),
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      collection.unclassified_semver_actions.each do |action|
        collection.serve_semver_from_repository_ref!(nwo: action.requested_nwo, ref: action.ref)
      end

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "actions/checkout", ref: "v4"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "actions/download-artifact", ref: "v4"),
      ]

      assert_equal collection.package_actions, []
      assert_equal collection.unservable_actions, []
      assert_equal collection.unclassified_semver_actions, []
    end

    test "Repository actions can be iterated over while the collection is being modified" do
      input = [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "actions/checkout", ref: "34f72ac1a25099eec59f2ddd9e6a803d381b7688"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "actions/setup-go", ref: "a72f4ef636fa9771fcc6fbb428fb07148f983d91"),
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      collection.repository_actions.each do |action|
        collection.impossible_to_serve!(nwo: action.requested_nwo, ref: action.ref, error: :blocked_action)
      end

      assert_equal collection.unservable_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(
          requested_nwo: "actions/checkout",
          ref: "34f72ac1a25099eec59f2ddd9e6a803d381b7688",
          normalised_semver: nil,
          error: :blocked_action),
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(
          requested_nwo: "actions/setup-go",
          ref: "a72f4ef636fa9771fcc6fbb428fb07148f983d91",
          normalised_semver: nil,
          error: :blocked_action),
      ]

      assert_equal collection.package_actions, []
      assert_equal collection.repository_actions, []
      assert_equal collection.unclassified_semver_actions, []
    end

    test "Marking only works with raw refs" do
      input = [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", ref: "v3"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "c/d", ref: "v2.0"),

        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", ref: "v4"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "g/h", ref: "V5"),

        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", ref: "v3.4"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "h/k", ref: "v9")
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      ## Repository

      # Using the normalised semver
      assert_raises ArgumentError do
        collection.serve_semver_from_repository_ref!(nwo: "a/b", ref: "3.*")
      end
      # Using the raw ref
      collection.serve_semver_from_repository_ref!(nwo: "c/d", ref: "v2.0")

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "c/d", ref: "v2.0")
      ]

      ## Packages

      # Using the normalise semver
      assert_raises ArgumentError do
        collection.serve_semver_from_package_version!(nwo: "e/f", ref: "4.x",
          full_semver: "4.2.1",
          package_id: 20,
          package_visibility: :public)
      end
      # Using the raw ref
      collection.serve_semver_from_package_version!(nwo: "g/h", ref: "V5",
        full_semver: "5.3.0",
        package_id: 21,
        package_visibility: :public)

      assert_equal collection.package_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::PackageAction.new(requested_nwo: "g/h", ref: "V5",
          normalised_semver: "5.*",
          full_semver: "5.3.0",
          package_id: 21,
          package_visibility: :public)
      ]

      ## Unservable

      # Using the normalised semver
      assert_raises ArgumentError do
        collection.impossible_to_serve!(nwo: "i/j", ref: "3.4.x", error: :version_not_found)
      end
      # Using the raw ref
      collection.impossible_to_serve!(nwo: "h/k", ref: "v9", error: :namespace_retired)

      assert_equal collection.unservable_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(requested_nwo: "h/k", ref: "v9", normalised_semver: "9.*", error: :namespace_retired),
      ]
    end

    test "Marking only works with requested nwo" do
      input = [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", processed_nwo: "aa/b", ref: "v3"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "c/d", processed_nwo: "cc/d", ref: "v2.0"),

        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "e/f", processed_nwo: "ee/f", ref: "v4"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "g/h", processed_nwo: "gg/h", ref: "V5"),

        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "i/j", processed_nwo: "ii/j", ref: "v3.4"),
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "h/k", processed_nwo: "hh/k", ref: "v9")
      ]

      collection = Actions::Resolver::V2::Internal::ActionsCollection.new(input)

      ## Repository

      # Using the requested nwo
      collection.serve_semver_from_repository_ref!(nwo: "a/b", ref: "v3")
      # Using the processed nwo
      assert_raises ArgumentError do
        collection.serve_semver_from_repository_ref!(nwo: "cc/d", ref: "v2.0")
      end

      assert_equal collection.repository_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(requested_nwo: "a/b", processed_nwo: "aa/b", ref: "v3")
      ]

      ## Packages

      # Using the requested nwo
      collection.serve_semver_from_package_version!(nwo: "e/f", ref: "v4",
        full_semver: "4.2.1",
        package_id: 20,
        package_visibility: :public)
      # Using the processed nwo
      assert_raises ArgumentError do
        collection.serve_semver_from_package_version!(nwo: "gg/h", ref: "V5",
          full_semver: "5.3.0",
          package_id: 21,
          package_visibility: :public)
      end

      assert_equal collection.package_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::PackageAction.new(requested_nwo: "e/f", processed_nwo: "ee/f", ref: "v4",
          normalised_semver: "4.*",
          full_semver: "4.2.1",
          package_id: 20,
          package_visibility: :public)
      ]

      ## Unservable

      # Using the requested nwo
      collection.impossible_to_serve!(nwo: "i/j", ref: "v3.4", error: :namespace_retired)
      # Using the processed nwo
      assert_raises ArgumentError do
        collection.impossible_to_serve!(nwo: "hh/k", ref: "v9", error: :access_denied)
      end

      assert_equal collection.unservable_actions, [
        Actions::Resolver::V2::Internal::ActionsCollection::UnservableAction.new(requested_nwo: "i/j", processed_nwo: "ii/j", ref: "v3.4", normalised_semver: "3.4.*", error: :namespace_retired)
      ]
    end
  end
end
