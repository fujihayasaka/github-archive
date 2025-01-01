# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationVersionDifferForTwoIntegrationVersionsTest < GitHub::TestCase
  fixtures { @integration = create(:integration, default_permissions: { "metadata" => :read }) }

  context "events" do
    context "added" do
      test "returns the list of added events" do
        version1 = make_integration_version
        version2 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal(%w(label), differ.events_added)
      end

      test "returns true if events were added" do
        version1 = make_integration_version
        version2 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :events_added?
        assert_predicate differ, :events_changed?
      end
    end

    context "removed" do
      test "returns the list of removed events" do
        version1 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        version2 = make_integration_version
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal(%w(label), differ.events_removed)
      end

      test "returns true if events were removed" do
        version1 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        version2 = make_integration_version
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :events_removed?
        assert_predicate differ, :events_changed?
      end
    end

    context "unchanged" do
      test "returns the list of unchanged events" do
        version1 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        version2 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal %w(label), differ.events_unchanged
      end

      test "returns true if events were unchanged" do
        version1 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        version2 = make_integration_version(default_permissions: { "metadata" => :read }, default_events: %w(label))
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :events_unchanged?
        refute_predicate differ, :events_changed?
      end
    end
  end

  context "permissions" do
    context "added" do
      test "returns the set of permissions added" do
        version1 = make_integration_version
        version2 = make_integration_version(default_permissions: { "contents" => :read })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal({ "contents" => :read }, differ.permissions_added)
      end

      test "returns true if permissions were added" do
        version1 = make_integration_version
        version2 = make_integration_version(default_permissions: { "contents" => :read })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :permissions_added?
        assert_predicate differ, :permissions_changed?
      end
    end

    context "downgraded" do
      test "returns the set of permissions downgraded" do
        version1 = make_integration_version(default_permissions: { "contents" => :write })
        version2 = make_integration_version(default_permissions: { "contents" => :read })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal({ "contents" => :read }, differ.permissions_downgraded)
      end

      test "returns true if permissions were downgraded" do
        version1 = make_integration_version(default_permissions: { "contents" => :write })
        version2 = make_integration_version(default_permissions: { "contents" => :read })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :permissions_downgraded?
        assert_predicate differ, :permissions_changed?
      end
    end

    context "removed" do
      test "returns the set of permissions removed" do
        version1 = make_integration_version(default_permissions: { "contents" => :write })
        version2 = make_integration_version
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal({ "contents" => :write }, differ.permissions_removed)
      end

      test "returns true if permissions were removed" do
        version1 = make_integration_version(default_permissions: { "contents" => :write })
        version2 = make_integration_version
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :permissions_removed?
        assert_predicate differ, :permissions_changed?
      end
    end

    context "unchanged" do
      test "returns the set of permissions unchanged" do
        version1 = make_integration_version(default_permissions: { "contents" => :read, "metadata" => :read })
        version2 = make_integration_version(default_permissions: { "contents" => :write, "metadata" => :read })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal({ "metadata" => :read }, differ.permissions_unchanged)
      end

      test "returns true if permissions were unchanged" do
        version1 = make_integration_version
        version2 = make_integration_version
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :permissions_unchanged?
        refute_predicate differ, :permissions_changed?
      end
    end

    context "upgraded" do
      test "returns the set of permissions upgraded" do
        version1 = make_integration_version(default_permissions: { "contents" => :read })
        version2 = make_integration_version(default_permissions: { "contents" => :write })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_equal({ "contents" => :write }, differ.permissions_upgraded)
      end

      test "returns true if permissions were upgraded" do
        version1 = make_integration_version(default_permissions: { "contents" => :read })
        version2 = make_integration_version(default_permissions: { "contents" => :write })
        differ   = permissions_differ(old_version: version1, new_version: version2)

        assert_predicate differ, :permissions_upgraded?
        assert_predicate differ, :permissions_changed?
      end
    end

    context "single file path" do
      context "added" do
        test "returns the single file paths added" do
          version1 = make_integration_version
          version2 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: ".travis.yml",
          )

          differ = permissions_differ(old_version: version1, new_version: version2)
          assert_equal %w(.travis.yml), differ.single_file_paths_added
        end

        test "returns true if a single file path was added" do
          version1 = make_integration_version
          version2 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: ".travis.yml",
          )

          differ = permissions_differ(old_version: version1, new_version: version2)

          assert_predicate differ, :single_file_paths_added?
        end
      end

      context "removed" do
        test "returns the single file paths removed" do
          version1 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: ".travis.yml",
          )
          version2 = make_integration_version

          differ = permissions_differ(old_version: version1, new_version: version2)
          assert_equal %w(.travis.yml), differ.single_file_paths_removed
        end

        test "returns true if a single file path was removed" do
          version1 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: ".travis.yml",
          )
          version2 = make_integration_version

          differ = permissions_differ(old_version: version1, new_version: version2)

          assert_predicate differ, :single_file_paths_removed?
        end
      end

      context "changed" do
        test "returns true if the single file paths were changed" do
          version1 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: ".travis.yml",
          )

          version2 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: "package.json",
          )

          differ = permissions_differ(old_version: version1, new_version: version2)

          assert_predicate differ, :single_file_paths_changed?
          refute_predicate differ, :single_file_paths_unchanged?
        end

        test "returns true if a single file path was added" do
          version1 = make_integration_version

          version2 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: "package.json",
          )

          differ = permissions_differ(old_version: version1, new_version: version2)

          assert_predicate differ, :single_file_paths_changed?
          refute_predicate differ, :single_file_paths_unchanged?
        end

        test "returns true if a single file path was removed" do
          version1 = make_integration_version(
            default_permissions: { "single_file" => :read },
            single_file_name: ".travis.yml",
          )

          version2 = make_integration_version

          differ = permissions_differ(old_version: version1, new_version: version2)

          assert_predicate differ, :single_file_paths_changed?
          refute_predicate differ, :single_file_paths_unchanged?
        end
      end

      context "unchanged" do
        context "with single file path" do
          test "returns the unchanged single file paths" do
            options = {
              default_permissions: { "single_file" => :read },
              single_file_name: ".travis.yml",
            }

            version1 = make_integration_version(options)
            version2 = make_integration_version(options)

            differ = permissions_differ(old_version: version1, new_version: version2)
            assert_equal %w(.travis.yml), differ.single_file_paths_unchanged
          end

          test "returns true if the single file paths are unchanged" do
            options = {
              default_permissions: { "single_file" => :read },
              single_file_name: ".travis.yml",
            }

            version1 = make_integration_version(options)
            version2 = make_integration_version(options)
            differ   = permissions_differ(old_version: version1, new_version: version2)

            assert_predicate differ, :single_file_paths_unchanged?
            refute_predicate differ, :single_file_paths_changed?
          end
        end

        context "without single file path" do
          test "returns an empty array" do
            version1 = make_integration_version
            version2 = make_integration_version
            differ   = permissions_differ(old_version: version1, new_version: version2)

            assert_equal [], differ.single_file_paths_unchanged
          end

          test "returns true if the single file paths are unchanged" do
            version1 = make_integration_version
            version2 = make_integration_version
            differ   = permissions_differ(old_version: version1, new_version: version2)

            assert_predicate differ, :single_file_paths_unchanged?
            refute_predicate differ, :single_file_paths_changed?
          end
        end
      end
    end
  end

  private

  def make_integration_version(options = {})
    return @integration.versions.first if options.empty?

    options[:integration] = @integration
    create(:integration_version, options)
  end

  def permissions_differ(old_version:, new_version:)
    IntegrationVersion::Differ.perform(
      old_version: old_version,
      new_version: new_version,
    )
  end
end
