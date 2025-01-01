# typed: true
# frozen_string_literal: true

require "test_helper"

module PackageRegistry
  class PackageVersionTest < GitHub::TestCase
    setup do
      @timey_object = stub(nanos: 1000000, seconds: 10)
      @metadata = stub
      @version = stub(created_at: @timey_object, updated_at: @timey_object, deleted_at: @timey_object, ecosystem: "Container", containerMetadata: @metadata)
      @subject = PackageVersion.new(@version)
    end

    context "#uri" do
      test "nil tag name" do
        tag = stub(digest: "sha12345", name: nil)
        @metadata.stubs(tag: tag)

        assert_equal "@sha12345", @subject.uri
      end

      test "blank tag name" do
        tag = stub(digest: "sha12345", name: "")
        @metadata.stubs(tag: tag)

        assert_equal "@sha12345", @subject.uri
      end

      test "tag name" do
        tag = stub(name: "latest")
        @metadata.stubs(tag: tag)

        assert_equal ":latest", @subject.uri
      end
    end

    test "#created_at" do
      assert_equal Time.at(10, 1000), @subject.created_at
    end

    test "#updated_at" do
      assert_equal Time.at(10, 1000), @subject.updated_at
    end

    test "#deleted_at" do
      assert_equal Time.at(10, 1000), @subject.deleted_at
    end

    context "#license" do
      test "container ecosystem with labels" do
        @version.stubs(:ecosystem).returns("container")
        @metadata.stubs(:labels).returns(stub(licenses: "LICENSE"))
        assert_equal "LICENSE", @subject.license
      end

      test "container ecosystem without labels" do
        @version.stubs(:ecosystem).returns("container")
        @metadata.stubs(:labels).returns(nil)
        assert_nil @subject.license
      end

    end

    context "#platforms" do
      test "returns correctly parsed, sorted and unique array of PackageRegistry::ContainerPlatform instances" do
        platforms_content = '
          [
            {"digest":"sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55","os":"linux","architecture":"arm"},
            {"digest":"sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55","os":"linux","architecture":"arm"},
            {"digest":"sha256:9e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d56","os":"linux","architecture":"arm","variant":"v6"},
            {"digest":"sha256:26a5d8b821fa539904b29baaa86535135980cab7063fddc697ae6c40f885733a","os":"linux","architecture":"amd64"}
          ]
        '
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: { "github.internal.platforms" => platforms_content }),
            manifest: stub(media_type: "application/vnd.docker.distribution.manifest.list.v2+json")
          )
        ))

        assert_equal 3, version.platforms.size

        amd64, arm, armv6 = version.platforms

        assert_equal "linux", arm.os
        assert_equal "arm", arm.architecture
        assert_equal "sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55", arm.digest

        assert_equal "linux", armv6.os
        assert_equal "arm", armv6.architecture
        assert_equal "sha256:9e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d56", armv6.digest
        assert_equal "v6", armv6.variant

        assert_equal "linux", amd64.os
        assert_equal "amd64", amd64.architecture
        assert_equal "sha256:26a5d8b821fa539904b29baaa86535135980cab7063fddc697ae6c40f885733a", amd64.digest
      end

      test "returns empty array when not multi-arch image" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: {})
          )
        ))
        assert_empty version.platforms
      end

      # rubocop:disable Layout/SpaceInsideHashLiteralBraces
      # The JSON with the `}` in it causes an autocorrector infinite loop.
      test "returns empty array and logs error when parsing invalid json" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: { "github.internal.platforms" =>                                                                                                                                                                                                                                                                                                                                                                                                                 "{"}),
            manifest: stub(media_type: "application/vnd.docker.distribution.manifest.list.v2+json")
          )
        ))

        GitHub.logger.expects(:info).once
        assert_empty version.platforms
      end
    end
    # rubocop:enable Layout/SpaceInsideHashLiteralBraces

    context "#multi_arch?" do
      test "returns true if docker manifest list" do
        platforms_content = '
          [
            {"digest":"sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55","os":"linux","architecture":"arm"},
            {"digest":"sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55","os":"linux","architecture":"arm","variant":"v6"},
            {"digest":"sha256:26a5d8b821fa539904b29baaa86535135980cab7063fddc697ae6c40f885733a","os":"linux","architecture":"amd64"}
          ]
        '
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: { "github.internal.platforms" => platforms_content }),
            manifest: stub(media_type: "application/vnd.docker.distribution.manifest.list.v2+json")
          )
        ))

        assert version.multi_arch?
      end

      test "returns true if oci image index" do
        platforms_content = '
          [
            {"digest":"sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55","os":"linux","architecture":"arm"},
            {"digest":"sha256:8e3db1495d7a9841a5d726cc51edc9af8d59dc5d06674bb7b58d2d3fe79f7d55","os":"linux","architecture":"arm","variant":"v6"},
            {"digest":"sha256:26a5d8b821fa539904b29baaa86535135980cab7063fddc697ae6c40f885733a","os":"linux","architecture":"amd64"}
          ]
        '
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: { "github.internal.platforms" => platforms_content }),
            manifest: stub(media_type: "application/vnd.oci.image.index.v1+json")
          )
        ))

        assert version.multi_arch?
      end

      test "returns false if not multi-arch" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: {}),
            manifest: stub(media_type: "application/vnd.docker.distribution.v2+json")
          )
        ))

        refute version.multi_arch?
      end
    end

    context "#deleted?" do
      test "returns true if deleted_at is present" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          deleted_at: @timey_object
        ))

        assert version.deleted?
      end

      test "returns false if deleted_at is not present" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          deleted_at: nil
        ))

        refute version.deleted?
      end
    end

    context "#tags" do
      test "returns tags for the version" do
        tags = [
          stub(name: "latest"),
          stub(name: "3.11.1")
        ]
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            tags: tags
          )
        ))

        assert_same_elements(version.tags, tags)
      end

      test "returns tags for the version, excludes latest" do
        tags = [
          stub(name: "latest"),
          stub(name: "3.11.1")
        ]
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            tags: tags
          )
        ))

        assert_same_elements(version.tags(include_latest: false), [tags[1]])
      end
    end

    context "#labels" do
      test "returns all labels excluding internal" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: { "test.label" => "foo", "github.internal.test" => "bar" })
          )
        ))

        labels = { "test.label" => "foo" }
        assert_equal labels, version.labels
      end

      test "returns all labels including internal" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            labels: stub(all_labels: { "test.label" => "foo", "github.internal.test" => "bar" })
          )
        ))

        labels = { "test.label" => "foo", "github.internal.test" => "bar" }
        assert_equal labels, version.labels(exclude_internal: false)
      end
    end

    context "#manifest_has_layers" do
      test "returns true if manifest file has non-empty layer object" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            manifest: { "abc" => "bcd", "layers" => [{ "abc" => "defh" }] }
          )
        ))

        assert version.manifest_has_layers
      end

      test "returns false if manifest file has empty layer object" do
        version = PackageVersion.new(stub(
          ecosystem: :container,
          containerMetadata: stub(
            manifest: { "abc" => "bcd" }
          )
        ))

        refute version.manifest_has_layers
      end
    end
  end
end
