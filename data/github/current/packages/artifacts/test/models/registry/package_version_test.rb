# typed: false
# frozen_string_literal: true

require "test_helper"

class RegistryPackageVersionTest < GitHub::TestCase
  include GitHub::RegistryPackageHelper
  include HydroTestHelpers
  include CdnTestHelper
  include Registry::PackageDownloadStatsService

  fixtures do
    @user1 = create :user, login: "scottjg", password: GitHub.default_password
    @repo = create :repository, owner: @user1, from_example: :repository_test_simple

    @repo2 = create :repository, owner: @user1, from_example: :repository_test_simple

    @user2 = create :user, login: "skalnik", password: GitHub.default_password
    @repo3 = create(:public_repository, owner: @user2, from_example: :repository_test_simple)

    @package = Registry::Package.new(
      name: "irrelevant-package",
      repository: @repo,
      owner: @repo.owner,
      package_type: :npm,
    )

    @version = make_registry_package_version(registry_package: @package, tag_name: "0.0.1")
    @version2 = make_registry_package_version(registry_package: @package, tag_name: "0.0.3") # so we don't delete the entire package when deleting @version

    @package.package_versions << @version
    @package.package_versions << @version2
    @package.save
  end

  context ".unmigrated" do
    test "returns only unmigrated package versions" do
      assert_same_elements [@version, @version2], @package.package_versions.unmigrated.to_a

      migrated = make_registry_package_version(registry_package: @package, tag_name: "migrated")
      migrated.migration_state = :complete
      @package.package_versions << migrated
      @package.save

      assert_same_elements [@version, @version2], @package.package_versions.unmigrated.to_a
    end
  end

  context "#files_count" do
    test "keeps a counter cache of files count" do
      version_two = make_registry_package_version(registry_package: @package, tag_name: "0.0.2")
      @package.package_versions << version_two
      @package.save

      assert_equal 1, version_two.files_count

      version_two.files.build(size: 1, state: 1, filename: "foo-bar", sha256: "shalalala")
      version_two.save!

      assert_equal 2, version_two.files_count
    end
  end

  context "create two packages with the same name" do
    test "on different repos with same owner fails" do
      another_package = Registry::Package.new(
       id: 1234,
       name: @package.name,
       repository: @repo2,
       owner: @repo2.owner,
       package_type: :npm,
     )

      another_package.package_versions << make_registry_package_version(registry_package: another_package, tag_name: "0.0.1")
      refute another_package.save
    end

    test "on different repos with different owner ok" do
      another_package = Registry::Package.new(
        name: @package.name,
        repository: @repo3,
        owner: @repo3.owner,
        package_type: :npm,
      )

      another_package.package_versions << make_registry_package_version(registry_package: another_package, tag_name: "0.0.1")
      assert another_package.save
    end
  end

  context "after_destroy :destroy_package_if_last_version" do
    test "destroys package and release asset if last version" do
      refute_nil Registry::Package.find_by_id(@package.id)

      @version.destroy
      @version2.destroy

      assert_nil Registry::Package.find_by_id(@package.id)
      assert_nil Registry::PackageVersion.find_by_id(@version.id)
    end

    test "doesnt destroy package if there are versions remaining" do
      other_version = make_registry_package_version(registry_package: @package, tag_name: "0.0.2")
      other_version.save

      @version.destroy

      refute_nil Registry::Package.find_by_id(@package.id)
      assert_nil Registry::PackageVersion.find_by_id(@version.id)
    end
  end

  test "destroys associated records on destroy" do
    package = Registry::Package.new name: "test1",
      owner_id: @repo.owner.id,
      repository_id: @repo.id,
      package_type: :npm
    package_version = package.package_versions.build version: "1.0",
      author: @user1,
      sha256: "this-is-not-a-real-sha256"
    package_version.metadata.build(name: Registry::Metadatum::KEYS[:README], value: "lorem dimsum")
    package_file = package_version.files.build  size: 1, state: 1,
      filename: "test.jar", sha1: "abcdef", md5: "foobar"
    package.save!

    make_searchable(package, type: "registry_package")

    package_dependency = Registry::Dependency.create! name: "testdep1",
      version: ">= 1.0",
      dependency_type: 1,
      registry_package_version_id: package_version.id

    package_version.destroy

    assert_nil Registry::PackageVersion.find_by_id(package_version.id)
    assert_nil Registry::Package.find_by_id(package.id)
    assert_nil Registry::File.find_by_id(package_file.id)
    assert_nil Registry::Dependency.find_by_id(package_dependency.id)
    assert_equal 0, Registry::Metadatum.where(package_version_id: package_version.id).count
  end

  test "renders good body html for readme" do
    new_readme = <<~MARKDOWN
    # Hello

    Hi

    # Another heading

    Hi
    MARKDOWN

    @version.metadata.set(Registry::Metadatum::KEYS[:README], new_readme)

    assert @version.reload.body_html.include?("anchor")
  end

  test "long readme is truncated correctly" do
    version_one = create :registry_package_version, package: @package
    @package.package_versions << version_one
    @package.save!

    # generate a README of more than 65535 bytes
    test_string = "0" * 70000
    version_one.metadata.create!(name: Registry::Metadatum::KEYS[:README], value: test_string)
    @package.save
    # now check that the value stored was no more than 65535 bytes
    @package.reload
    @package.package_versions.each do |v|
      assert v.metadata.readme.bytesize <= 65535
    end
  end

  test "long unicode readme is truncated correctly" do
    version_one = create :registry_package_version, package: @package
    @package.package_versions << version_one
    @package.save!

    # generate a README of more than 65535 bytes, containing unicode characters
    test_string = "\u043B" * 70000
    version_one.metadata.create!(name: Registry::Metadatum::KEYS[:README], value: test_string)
    @package.save
    # now check that the value stored was no more than 65535 bytes
    @package.reload
    @package.package_versions.each do |v|
      assert v.metadata.readme.bytesize <= 65535
    end
  end

  test "updates latest tag on create" do
    @package.package_type = :rubygems
    new_version = make_registry_package_version(registry_package: @package, tag_name: "0.0.4")
    @package.package_versions << new_version
    @package.save!
    tag = Registry::Tag.where(name: "latest", registry_package_id: @package.id).first
    refute_nil tag, "latest tag should be created on new record"
    assert_equal new_version.id, tag.registry_package_version_id
  end

  test "updates latest tag on destroy" do
    @package.package_type = :rubygems
    new_version = make_registry_package_version(registry_package: @package, tag_name: "0.0.4")
    @package.package_versions << new_version
    @package.save!

    tag = Registry::Tag.where(name: "latest", registry_package_id: @package.id).first
    refute_nil tag, "latest tag should be recreated, pointing to 0.0.4"

    @package.update! package_type: :rubygems

    assert_equal new_version.id, tag.registry_package_version_id
    assert new_version.reload.destroy

    refute_nil tag, "latest tag should be recreated, pointing to #{@version2.version}"
    tag = Registry::Tag.where(name: "latest", registry_package_id: @package.id).first
    assert_equal @version2.id, tag.registry_package_version_id
  end

  test "self.summaries_for_ids returns correct summaries" do
    version_one = create :registry_package_version, package: @package
    version_two = create :registry_package_version, package: @package
    version_three = create :registry_package_version, package: @package
    @package.package_versions << [version_one, version_two, version_three]
    @package.save!

    version_one.metadata.create!(name: Registry::Metadatum::KEYS[:SUMMARY], value: "This is the package summary")
    version_two.metadata.create!(name: Registry::Metadatum::KEYS[:SUMMARY], value: "lorem \xC2\xA9 dimsum".b)
    version_three.metadata.create!(name: Registry::Metadatum::KEYS[:SUMMARY], value: "")

    expected = {
      version_one.id => "This is the package summary",
      version_two.id => "lorem \xC2\xA9 dimsum",
      version_three.id => nil
    }

    assert_equal expected, Registry::PackageVersion.summaries_for_ids([version_one.id, version_two.id, version_three.id])
  end

  test "self.dependency_counts_for_ids returns correct counts" do
    version = make_registry_package_version(registry_package: @package, tag_name: "0.0.4")
    @package.package_versions << version
    @package.save!

    Registry::Dependency.create! name: "foo",
      version: ">= 1.0",
      dependency_type: 1,
      registry_package_version_id: version.id
    Registry::Dependency.create! name: "bar",
      version: ">= 2.0",
      dependency_type: 1,
      registry_package_version_id: version.id

    expected = { version.id => 2 }

    assert_equal expected, Registry::PackageVersion.dependency_counts_for_ids(version.id)
  end

  context ".latest" do
    test "doesnt return docker-base-layer if its the only version" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )

      Timecop.freeze(Date.parse "2017-10-01") do
        version = make_registry_package_version(registry_package: package, tag_name: "docker-base-layer")
        package.package_versions << version
        package.save
        version
      end

      assert_empty package.package_versions.latest.to_a
    end

    test "returns version tagged 'latest' first followed by other versions in order of update" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )

      v1 = Timecop.freeze(Date.parse "2017-10-01") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1")
        package.package_versions << version
        package.save
        version
      end

      v2 = Timecop.freeze(Date.parse "2017-10-02") do
        version = make_registry_package_version(registry_package: package, tag_name: "v2")
        package.package_versions << version
        package.save
        version
      end

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      Registry::Tag.create!(name: "latest", registry_package_version_id: v2.id, registry_package_id: package.id)
      latest = package.package_versions.latest.to_a
      assert_equal 3, latest.count
      assert_equal [v2, v1dot1, v1], latest
    end

    test "returns versions in order of update if no 'latest' tag" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :docker,
      )

      v1 = Timecop.freeze(Date.parse "2017-10-01") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1")
        package.package_versions << version
        package.save
        version
      end

      v2 = Timecop.freeze(Date.parse "2017-10-02") do
        version = make_registry_package_version(registry_package: package, tag_name: "v2")
        package.package_versions << version
        package.save
        version
      end

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      latest = package.package_versions.latest.to_a
      assert_equal 3, latest.count
      assert_equal [v1dot1, v2, v1], latest
    end
  end

  context ".summary" do
    test "returns empty string if no summary" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      assert_equal 0, new_version.summary.length
      assert_equal "", new_version.summary
    end

    test "returns valid string if summary metadata is set" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      new_version.metadata.create!(name: Registry::Metadatum::KEYS[:SUMMARY], value: "This is the package summary")
      assert_equal "This is the package summary", new_version.summary
    end

    test "returns UTF-8 string if summary metadata is not UTF-8-encoded" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      new_version.metadata.create!(name: Registry::Metadatum::KEYS[:SUMMARY], value: GitHub::RegistryPackageHelper::NON_UTF8_METADATA_VALUE)
      assert_equal GitHub::RegistryPackageHelper::SCRUBBED_UTF8_METADATA_VALUE, new_version.summary
      assert_equal Encoding::UTF_8, new_version.summary.encoding
    end
  end

  context ".package_manifest" do
    test "returns nil if no manifest" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      assert_nil new_version.package_manifest
    end

    test "returns docker manifest if package is of type docker." do
      docker_package = Registry::Package.new(
        name: "docker-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :docker,
      )
      new_version = docker_package.package_versions.build(version: "1.0", author: @repo.owner)
      docker_package.save!
      new_version.metadata.create!(name: Registry::Metadatum::KEYS[:DOCKER_IMAGE_MANIFEST], value: "This is the docker manifest")
      assert_equal "This is the docker manifest", new_version.package_manifest
    end

    test "returns docker manifest if both manifest and the metadata value was set" do
      docker_package = Registry::Package.new(
        name: "docker-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :docker,
      )
      new_version = docker_package.package_versions.build(version: "1.0", author: @repo.owner, manifest: "This is the correct docker manifest")
      docker_package.save!
      new_version.metadata.create!(name: Registry::Metadatum::KEYS[:DOCKER_IMAGE_MANIFEST], value: "This is the wrong docker manifest")
      assert_equal "This is the correct docker manifest", new_version.package_manifest
    end

    test "returns manifest if docker manifest is not set." do
      new_version = create :registry_package_version, package: @package
      new_version.manifest = "This is the correct docker manifest"
      @package.package_versions << new_version
      @package.save!
      assert_equal "This is the correct docker manifest", new_version.package_manifest
    end

    test "returns UTF-8 manifest if the package is not of type docker and the manifest value was not UTF-8" do
      new_version = create :registry_package_version, package: @package
      new_version.manifest = GitHub::RegistryPackageHelper::NON_UTF8_METADATA_VALUE
      @package.package_versions << new_version
      @package.save!
      new_version = Registry::PackageVersion.find(new_version.id)
      assert_equal GitHub::RegistryPackageHelper::SCRUBBED_UTF8_METADATA_VALUE, new_version.package_manifest
      assert_equal Encoding::UTF_8, new_version.package_manifest.encoding
    end
  end

  context ".validate author" do
    test "fails to create version with no author" do
      release = create(:release, tag_name: "0.0.2", repository: @package.repository, author: @user1)
      new_version = build :registry_package_version, package: @package, release: release, author: nil
      @package.package_versions << new_version

      assert_raises(ActiveRecord::RecordInvalid) do
        @package.save!
      end
    end

    test "soft-deletes version successfully if author no longer exists" do
      @repo.update!(public: false)
      assert @repo.private?
      @user1.delete
      @version.delete!(actor: @user2)

      assert @version.reload.deleted?
    end
  end

  context ".installation_command" do
    test "returns empty string if no command" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      assert_equal 0, new_version.installation_command.length
      assert_equal "", new_version.installation_command
    end

    test "returns command if specified" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      new_version.metadata.create!(name: Registry::Metadatum::KEYS[:INSTALLATION_COMMAND], value: "Hope for the best!")
      assert_equal "Hope for the best!", new_version.installation_command
    end

    test "returns UTF-8 string if command is not UTF-8-encoded" do
      new_version = create :registry_package_version, package: @package
      @package.package_versions << new_version
      @package.save!
      new_version.metadata.create!(name: Registry::Metadatum::KEYS[:INSTALLATION_COMMAND], value: GitHub::RegistryPackageHelper::NON_UTF8_METADATA_VALUE)
      assert_equal GitHub::RegistryPackageHelper::SCRUBBED_UTF8_METADATA_VALUE, new_version.installation_command
      assert_equal Encoding::UTF_8, new_version.installation_command.encoding
    end
  end

  context ".delete!" do
    test "decreases storage utilization on delete" do
      @repo.update!(public: false)
      assert @repo.private?
      old_utilization = Registry::PackageStorageUtilizations.find_by(owner: @user1)

      @version.delete!

      new_utilization = Registry::PackageStorageUtilizations.find_by(owner: @user1)

      assert new_utilization.gb_used < old_utilization.gb_used
    end

    test "does not decrease storage utilization below 0" do
      @repo.update!(public: false)

      old_utilization = Registry::PackageStorageUtilizations.find_by(owner: @user1)

      # Set the utilization to 0 without running callbacks so we can test this behavior
      old_utilization.update_column(:gb_used, 0)

      @version.delete!

      new_utilization = Registry::PackageStorageUtilizations.find_by(owner: @user1)

      assert_equal 0, new_utilization.gb_used
    end

    test "sets deleted_at, deleted_by on the package version" do
      @repo.update!(public: false)
      assert @repo.private?

      # if this were an npm package, the client will have tagged the latest version so we need to make sure it gets moved
      latest_tag = Registry::Tag.new(name: "latest", registry_package_id: @package.id, registry_package_version_id: @version.id)
      latest_tag.save

      assert_equal @version.id, latest_tag.registry_package_version_id

      Timecop.freeze do
        @version.delete!(actor: @user1)
        assert @version.reload.deleted_at - Time.now < 1
        assert_equal @user1, @version.reload.deleted_by

        latest_tag = Registry::Tag.where(name: "latest", registry_package_id: @package.id).first
        assert_equal @version2.id, latest_tag.registry_package_version_id
      end
    end

    test "raises error if package version is public and has more than #{PUBLIC_VERSION_DELETE_LIMIT} downloads" do
      @repo.update!(public: true)
      assert @repo.public?

      (PUBLIC_VERSION_DELETE_LIMIT + 1).times { Registry::PackageDownloadActivity.track(@package.id, @version.id, Time.now) }

      assert_equal (PUBLIC_VERSION_DELETE_LIMIT + 1), @version.downloads_total_count

      assert_raises Registry::PackageVersion::PackageVersionDeletionError do
        @version.delete!(actor: @user1)
      end

      assert_nil @version.deleted_at
    end

    test "allow deletion if package version belongs to a public repository in feature flag" do
      @repo.update!(public: true)
      assert @repo.public?

      Timecop.freeze do
        @version.delete!(actor: @user1)
        assert @version.reload.deleted_at - Time.now < 1
        assert_equal @user1, @version.reload.deleted_by
      end
    end

    test "handles when the parent repository has been deleted" do
      @repo.delete
      @version.reload
      @version.delete!(actor: @owner)
      assert @version.reload.deleted?
    end

    test "instruments package version deleted event" do
      skip unless GitHub.hydro_enabled?

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({ request_id: request_id })

      @repo.update!(public: false)
      assert @repo.private?

      @version.delete!(actor: @owner, user_agent: nil)

      # Hydro::EntitySerializer#package requires the repository association to be
      # loaded. This is done in authorization checks in the execute_query flow
      # but we need to manually load it when building the message from scratch.
      @package.reload
      @version.reload
      @version.package
      @package.repository
      assert @package.association(:repository).loaded?

      message = {
        request_context: Hydro::EntitySerializer.request_context({ request_id: request_id }),
        actor: Hydro::EntitySerializer.user(@owner),
        package: Hydro::EntitySerializer.package(@package),
        version: Hydro::EntitySerializer.package_version(@version, size: @version.files.sum(:size), files_count: @version.files.count),
        deleted_at: @version.reload.deleted_at,
        storage_service: { name: "AWS_S3" },
        user_agent: nil,
        via_actions: false,
        event_id: request_id,
      }

      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionDeleted")
      assert_hydro_published(message, schema: "package_registry.v0.PackageVersionDeleted")
    end

    test "doesn't instrument package version deleted event when version is docker-base-layer" do
      skip unless GitHub.hydro_enabled?

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({ request_id: request_id })

      @repo.update!(public: false)
      assert @repo.private?

      @package.package_type = :docker
      @package.save!
      @version.version = "docker-base-layer"
      @version.save!

      @version.delete!(actor: @owner, user_agent: nil)

      assert_hydro_messages(count: 0, schema: "package_registry.v0.PackageDeleted")
      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionDeleted")
    end

    test "instruments package file destroyed event" do
      skip unless GitHub.hydro_enabled?

      @repo.update!(public: false)
      assert @repo.private?

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({ request_id: request_id })

      package = Registry::Package.new(
          name: "package-file-destroy",
          repository: @repo,
          owner: @repo.owner,
          package_type: :npm,
      )
      package_version = package.package_versions.build version: "1.0",
                                                       author: @user1,
                                                       sha256: "this-is-not-a-real-sha256"

      package_version.files.build  size: 1, state: 1, filename: "some_file.jar", sha1: "abcdef", md5: "foobar"
      package.save!

      message = {
          artifact_id: package.package_versions.first.package_files.first.guid,
          storage_service: { name: "AWS_S3" },
          event_id: request_id,
          repository: { id: @repo.id },
      }

      package_version.destroy!

      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageFileDestroyed")
      assert_hydro_published(message, schema: "package_registry.v0.PackageFileDestroyed", ignore_extra_keys: true)
    end

    test "docker deletion only destroys orphaned layers" do
      skip unless GitHub.hydro_enabled?

      @repo.update!(public: false)
      assert @repo.private?

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({ request_id: request_id })

      package = Registry::Package.new(
          name: "docker-deletion-package",
          repository: @repo,
          owner: @repo.owner,
          package_type: :docker,
      )

      docker_base_version = package.package_versions.build version: "docker-base-layer",
                                                                   author: @user1,
                                                                   sha256: "base-layer-sha"

      # Create two docker containers (versions) with one shared layer between them
      package_version_1 = package.package_versions.build version: "1.0",
                                                         author: @user1,
                                                         sha256: "this-is-not-a-real-sha256"
      package_version_2 = package.package_versions.build version: "2.0",
                                                         author: @user1,
                                                         sha256: "this-is-also-not-a-real-sha256"
      package.save!

      # Create a file shared between the two versions, and a unique file per version
      f_shared = Registry::File.new(
          filename: "base-layer",
          registry_package_name: "pkg",
          registry_package_type: :docker,
          version: package_version_1.version,
          package_version_id: package_version_1.id,
          size: 1,
          sha256: "foo",
      )

      f_shared.package_version = docker_base_version
      f_shared.save!

      f_shared.package_version = package_version_1
      f_shared.save!

      f_shared.package_version = package_version_2
      f_shared.save!

      f_unique_1 = Registry::File.new(
          filename: "unique-layer-2",
          registry_package_name: "pkg",
          registry_package_type: :docker,
          version: package_version_1.version,
          package_version_id: package_version_1.id,
          size: 1,
          sha256: "bar",
      )

      f_unique_1.package_version = docker_base_version
      f_unique_1.save!

      f_unique_1.package_version = package_version_1
      f_unique_1.save!

      f_unique_2 = Registry::File.new(
          filename: "unique-layer-1",
          registry_package_name: "pkg",
          registry_package_type: :docker,
          version: package_version_1.version,
          package_version_id: package_version_1.id,
          size: 1,
          sha256: "baz",
      )

      f_unique_2.package_version = docker_base_version
      f_unique_2.save!

      f_unique_2.package_version = package_version_2
      f_unique_2.save!

      assert_equal 3, package.package_versions.count

      # Destroy one version, and assert that the shared layer was not destroyed from blob storage
      version_1_file_2_message = {
          artifact_id: f_unique_1.guid,
          storage_service: { name: "AWS_S3" },
          event_id: request_id,
          repository: { id: @repo.id },
      }

      package_version_1.destroy!

      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageFileDestroyed")
      assert_hydro_published(version_1_file_2_message, schema: "package_registry.v0.PackageFileDestroyed", ignore_extra_keys: true)

      reset_hydro

      # Destroy other version, and assert that both the unique and shared layers are destroyed from blob storage
      version_2_file_1_message = {
          artifact_id: f_shared.guid,
          storage_service: { name: "AWS_S3" },
          event_id: request_id,
          repository: { id: @repo.id },
      }

      version_2_file_2_message = {
          artifact_id: f_unique_2.guid,
          storage_service: { name: "AWS_S3" },
          event_id: request_id,
          repository: { id: @repo.id },
      }

      package_version_2.destroy!

      assert_hydro_published(version_2_file_1_message, schema: "package_registry.v0.PackageFileDestroyed", ignore_extra_keys: true)
      assert_hydro_published(version_2_file_2_message, schema: "package_registry.v0.PackageFileDestroyed", ignore_extra_keys: true)
    end

    test "docker deletion releases appropriate resource utilization in billing events" do
      skip unless GitHub.hydro_enabled?

      @repo.update!(public: false)
      assert @repo.private?

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({
          console_host: "ops-shell-123456.ash1-iad.github.net",
          request_id: request_id,
      })


      package = Registry::Package.new(
          name: "docker-deletion-package",
          repository: @repo,
          owner: @repo.owner,
          package_type: :docker,
      )

      package.save!

      # Versions must be created at least 1 sec apart to distinguish "latest version"
      docker_base_version = Timecop.freeze(2020, 03, 10, hour = 12, minute = 15, second = 0) do
        package.package_versions.create version: "docker-base-layer",
                                        author: @user1,
                                        sha256: "base-layer-sha"
      end

      # Create two docker containers (versions) with one shared layer between them
      package_version_1 = Timecop.freeze(2020, 03, 10, hour = 12, minute = 15, second = 1) do
        package.package_versions.create version: "1.0",
                                        author: @user1,
                                        sha256: "this-is-not-a-real-sha256"
      end

      package_version_2 = Timecop.freeze(2020, 03, 10, hour = 12, minute = 15, second = 2) do
        package.package_versions.create version: "2.0",
                                        author: @user1,
                                        sha256: "this-is-also-not-a-real-sha256"
      end

      # Create a file shared between the two versions, and a unique file per version
      f_shared = Registry::File.new(
          filename: "base-layer",
          registry_package_name: "pkg",
          registry_package_type: :docker,
          version: package_version_1.version,
          package_version_id: package_version_1.id,
          size: 1,
          sha256: "foo",
      )

      f_shared.package_version = docker_base_version
      f_shared.save!

      f_shared.package_version = package_version_1
      f_shared.save!

      f_shared.package_version = package_version_2
      f_shared.save!

      f_unique_1 = Registry::File.new(
          filename: "unique-layer-2",
          registry_package_name: "pkg",
          registry_package_type: :docker,
          version: package_version_1.version,
          package_version_id: package_version_1.id,
          size: 10,
          sha256: "bar",
      )

      f_unique_1.package_version = docker_base_version
      f_unique_1.save!

      f_unique_1.package_version = package_version_1
      f_unique_1.save!

      f_unique_2 = Registry::File.new(
          filename: "unique-layer-1",
          registry_package_name: "pkg",
          registry_package_type: :docker,
          version: package_version_1.version,
          package_version_id: package_version_1.id,
          size: 100,
          sha256: "baz",
      )

      f_unique_2.package_version = docker_base_version
      f_unique_2.save!

      f_unique_2.package_version = package_version_2
      f_unique_2.save!

      assert_equal 3, package.package_versions.count

      package_version_1.delete!(actor: @owner, user_agent: nil)
      package_version_1.reload
      package_version_1.package.reload

      # Destroy one version, and assert that only the file unique to that container are reported as deleted to hydro for billing purposes
      version_1_deletion_message = {
        version: Hydro::EntitySerializer.package_version(package_version_1, size: 10, files_count: 1),
      }

      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionDeleted")
      assert_hydro_published(version_1_deletion_message, schema: "package_registry.v0.PackageVersionDeleted", ignore_extra_keys: true)

      reset_hydro

      # Destroy other version, and assert that both the unique and shared files are reported as deleted to hydro for billing purposes
      package_version_2.delete!(actor: @owner, user_agent: nil)

      assert_hydro_messages(count: 2, schema: "package_registry.v0.PackageVersionDeleted")
      messages = decoded_hydro_messages.select { |msg| msg.schema == "package_registry.v0.PackageVersionDeleted" }
      docker_base_version_deleted_message = messages.first.data.message
      package_version_2_deleted_message = messages.last.data.message

      assert_equal docker_base_version_deleted_message[:version][:version], docker_base_version.reload.original_name
      assert_equal docker_base_version_deleted_message[:version][:package_size], 0
      assert_equal docker_base_version_deleted_message[:version][:files_count], 0

      assert_equal package_version_2_deleted_message[:version][:version], package_version_2.original_name
      assert_equal package_version_2_deleted_message[:version][:package_size], (f_shared.size + f_unique_2.size)
      assert_equal package_version_2_deleted_message[:version][:files_count], 2
    end

    test "when there are no other active versions, docker-base-layer is deleted" do
      @repo.update!(public: false)
      assert @repo.private?

      docker_package = Registry::Package.new(
          name: "docker-package",
          repository: @repo,
          owner: @repo.owner,
          package_type: :docker,
      )

      base = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 0) do
        docker_base_layer = make_registry_package_version(registry_package: docker_package, tag_name: "docker-base-layer")
        docker_package.package_versions << docker_base_layer
        docker_package.save
        docker_base_layer
      end

      v1 = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 1) do
        version = make_registry_package_version(registry_package: docker_package, tag_name: "1.0")
        docker_package.package_versions << version
        docker_package.save
        version
      end

      v1.delete!(actor: @user1)

      assert base.reload.deleted?
    end

    test "when there are no other active versions and the repo is public but force-delete is set, docker-base-layer is deleted" do
      @repo.update!(public: true)
      refute @repo.private?

      docker_package = Registry::Package.new(
          name: "docker-package",
          repository: @repo,
          owner: @repo.owner,
          package_type: :docker,
      )

      base = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 0) do
        docker_base_layer = make_registry_package_version(registry_package: docker_package, tag_name: "docker-base-layer")
        docker_package.package_versions << docker_base_layer
        docker_package.save
        docker_base_layer
      end

      v1 = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 1) do
        version = make_registry_package_version(registry_package: docker_package, tag_name: "1.0")
        docker_package.package_versions << version
        docker_package.save
        version
      end

      v1.delete!(actor: @user1, force_delete: true)

      assert base.reload.deleted?
    end

    test "when no version is tagged 'latest' but active versions exist, docker-base-layer is not deleted" do
      @repo.update!(public: false)
      assert @repo.private?

      docker_package = Registry::Package.new(
          name: "docker-package",
          repository: @repo,
          owner: @repo.owner,
          package_type: :docker,
      )

      # Versions must be created at least 1sec apart to determine 'latest' because the db strips milliseconds from time
      # and they'd all have the same timestamp
      base = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 0) do
        docker_base_layer = make_registry_package_version(registry_package: docker_package, tag_name: "docker-base-layer")
        docker_package.package_versions << docker_base_layer
        docker_package.save
        docker_base_layer
      end

      v1 = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 1) do
        version = make_registry_package_version(registry_package: docker_package, tag_name: "1.0")
        docker_package.package_versions << version
        docker_package.save
        version
      end

      Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 2) do
        version = make_registry_package_version(registry_package: docker_package, tag_name: "2.0")
        docker_package.package_versions << version
        docker_package.save
        version
      end

      v1.delete!(actor: @user1)

      refute base.reload.deleted?
    end

    test "when version tagged 'latest' is deleted and another active version exists, docker-base-layer is not deleted" do
      @repo.update!(public: false)
      assert @repo.private?

      docker_package = Registry::Package.new(
          name: "docker-package",
          repository: @repo,
          owner: @repo.owner,
          package_type: :docker,
      )

      base = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 0) do
        docker_base_layer = make_registry_package_version(registry_package: docker_package, tag_name: "docker-base-layer")
        docker_package.package_versions << docker_base_layer
        docker_package.save
        docker_base_layer
      end

      Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 1) do
        version = make_registry_package_version(registry_package: docker_package, tag_name: "1.0")
        docker_package.package_versions << version
        docker_package.save
        version
      end

      v2 = Timecop.freeze(2020, 03, 04, hour = 12, minute = 15, second = 2) do
        version = make_registry_package_version(registry_package: docker_package, tag_name: "2.0")
        docker_package.package_versions << version
        docker_package.save
        version
      end

      Registry::Tag.create!(name: "latest", registry_package_version_id: v2.id, registry_package_id: @package.id)
      v2.delete!(actor: @user1)

      refute base.reload.deleted?
    end
  end

  context "#ensure_delete_event_instrumented" do
    test "instruments PackageVersionDeleted when version has not been deleted" do
      skip unless GitHub.hydro_enabled?

      Timecop.freeze do
        request_id = SecureRandom.uuid
        ::Context.any_instance.stubs(:to_hash).returns({
          console_host: "ops-shell-123456.ash1-iad.github.net",
          request_id: request_id,
        })

        @repo.update!(public: false)
        assert @repo.private?

        package_size = @version.files.sum(:size)
        file_count = @version.files.count

        @version.destroy

        # Hydro::EntitySerializer#package requires the repository association to be
        # loaded. This is done in authorization checks in the execute_query flow
        # but we need to manually load it when building the message from scratch.
        @package.repository
        assert @package.association(:repository).loaded?

        message = {
          request_context: Hydro::EntitySerializer.request_context({ console_host: "ops-shell-123456.ash1-iad.github.net", request_id: request_id }),
          actor: nil,
          package: Hydro::EntitySerializer.package(@package),
          version: Hydro::EntitySerializer.package_version(@version, size: package_size, files_count: file_count),
          deleted_at: Time.now,
          storage_service: { name: "AWS_S3" },
          user_agent: nil,
          via_actions: false,
          event_id: request_id,
        }

        assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionDeleted")
        assert_hydro_published(message, schema: "package_registry.v0.PackageVersionDeleted")
      end
    end

    test "does not instrument PackageVersionDeleted when version is deleted" do
      skip unless GitHub.hydro_enabled?

      @repo.update!(public: false)
      assert @repo.private?

      @version.delete!
      assert @version.deleted?

      reset_hydro

      @version.destroy

      assert_hydro_messages(count: 0, schema: "package_registry.v0.PackageVersionDeleted")
    end
  end

  context ".restore!" do
    test "sets deleted_at to nil" do
      @repo.update!(public: false)
      assert @repo.private?

      @version.delete!
      assert @version.deleted?

      @version.restore!
      refute @version.deleted?
      assert_nil @version.deleted_at
    end

    test "instruments package version published event" do
      skip unless GitHub.hydro_enabled?

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({ request_id: request_id })

      @repo.update!(public: false)
      assert @repo.private?
      @version.delete!(actor: @owner, user_agent: nil)
      assert @version.deleted?

      version_deleted_name = @version.version

      @version.restore!

      # Hydro::EntitySerializer#package requires the repository association to be
      # loaded. This is done in authorization checks in the execute_query flow
      # but we need to manually load it when building the message from scratch.
      @package.reload
      @version.reload
      @version.package
      @package.repository
      assert @package.association(:repository).loaded?

      message = {
        request_context: Hydro::EntitySerializer.request_context({ request_id: request_id }),
        actor: Hydro::EntitySerializer.user(@owner),
        package: Hydro::EntitySerializer.package(@package),
        version: Hydro::EntitySerializer.package_version(@version, size: @version.files.sum(:size), files_count: @version.files.count),
        published_at: @version.reload.updated_at,
        storage_service: { name: "AWS_S3" },
        user_agent: nil,
        via_actions: false,
        republished: true,
        event_id: request_id,
        version_deleted_name: version_deleted_name
      }

      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionPublished")
      assert_hydro_published(message, schema: "package_registry.v0.PackageVersionPublished")
    end

    test "instruments multiple package file published events if version has multiple files" do
      skip unless GitHub.hydro_enabled?

      @package.restore!

      request_id = SecureRandom.uuid
      ::Context.any_instance.stubs(:to_hash).returns({ request_id: request_id })

      @repo.update!(public: false)
      assert @repo.private?

      file_2 = Registry::File.new(size: 123, filename: "new_file", sha256: "sha123")
      @version.files << file_2
      @version.save

      @version.delete!(actor: @owner, user_agent: nil)
      assert @version.deleted?

      @version.restore!

      # Hydro::EntitySerializer#package requires the repository association to be
      # loaded. This is done in authorization checks in the execute_query flow
      # but we need to manually load it when building the message from scratch.
      @package.reload
      @version.reload
      @version.package
      @package.repository
      assert @package.association(:repository).loaded?
      assert @version.association(:package).loaded?

      message_1 = {
          request_context: Hydro::EntitySerializer.request_context({ request_id: request_id }),
          actor: Hydro::EntitySerializer.user(@owner),
          package: Hydro::EntitySerializer.package(@package),
          version: Hydro::EntitySerializer.package_version(@version, size: @version.files.sum(:size), files_count: @version.files.count),
          published_at: @version.reload.updated_at,
          storage_service: { name: "AWS_S3" },
          user_agent: nil,
          via_actions: false,
          file: Hydro::EntitySerializer.package_file(@version.files.first),
          event_id: request_id,
      }

      @version.package
      message_2 = {
          request_context: Hydro::EntitySerializer.request_context({ request_id: request_id }),
          actor: Hydro::EntitySerializer.user(@owner),
          package: Hydro::EntitySerializer.package(@package),
          version: Hydro::EntitySerializer.package_version(@version, size: @version.files.sum(:size), files_count: @version.files.count),
          published_at: @version.reload.updated_at,
          storage_service: { name: "AWS_S3" },
          user_agent: nil,
          via_actions: false,
          file: Hydro::EntitySerializer.package_file(file_2),
          event_id: request_id,
      }

      assert_hydro_messages(count: 2, schema: "package_registry.v0.PackageFilePublished")
      assert_hydro_published(message_1, schema: "package_registry.v0.PackageFilePublished")
      assert_hydro_published(message_2, schema: "package_registry.v0.PackageFilePublished")
    end

    test "restoration re-indexes search" do
      @repo.update!(public: false)
      assert @repo.private?

      @version.delete!
      assert @version.deleted?

      Search.expects(:add_to_search_index).at_least_once

      @version.restore!
    end

    test "does not restore a version if the parent package is deleted" do
      @repo.update!(public: false)
      assert @repo.private?

      @version.delete!
      assert @version.deleted?

      @package.delete!
      assert @package.deleted?
      @version.reload

      assert_raises Registry::PackageVersion::PackageVersionRestorationError do
        @version.restore!
      end

      assert @version.deleted?
    end
  end

  context ".total_download_counts_for_ids" do
    test "returns correct counts" do
      version = create(:registry_package_version, package: @package)
      version.files.build(size: 40, state: 1, filename: "test.jar", sha1: "abcdef", md5: "foobar")
      version.files.build(size: 60, state: 1, filename: "test2.jar", sha1: "abcdef", md5: "foobaz")
      version.save!

      assert_equal 3, version.files.count

      3.times { Registry::PackageDownloadActivity.track(@package.id, version.id, Time.now) }

      expected = { version.id => 1 }

      assert_equal expected, Registry::PackageVersion.total_download_counts_for_ids(version.id)
    end

    test "returns empty hash when version not found" do
      version = create(:registry_package_version, package: @package)
      destroyed_version_id = version.id
      version.destroy

      assert_empty Registry::PackageVersion.total_download_counts_for_ids(destroyed_version_id)
    end

    test "returns 0 for deleted versions" do
      version = create(:registry_package_version, package: @package)

      Registry::PackageDownloadActivity.track(@package.id, version.id, Time.now)

      version.delete!(force_delete: true)

      expected = { version.id => 0 }

      assert_equal expected, Registry::PackageVersion.total_download_counts_for_ids(version.id)
    end
  end

  context ".thirty_day_download_counts_for_ids" do
    test "only counts downloads in last thirty days" do
      version = create(:registry_package_version, package: @package)

      Registry::PackageDownloadActivity.track(@package.id, version.id, 60.days.ago)
      Registry::PackageDownloadActivity.track(@package.id, version.id, 35.days.ago)
      Registry::PackageDownloadActivity.track(@package.id, version.id, 20.days.ago)
      Registry::PackageDownloadActivity.track(@package.id, version.id, 2.days.ago)

      expected = { version.id => 2 }

      assert_equal expected, Registry::PackageVersion.thirty_day_download_counts_for_ids(version.id)
    end

    test "returns 0 if all downloads older than thirty days" do
      version = create(:registry_package_version, package: @package)

      Registry::PackageDownloadActivity.track(@package.id, version.id, 60.days.ago)
      Registry::PackageDownloadActivity.track(@package.id, version.id, 35.days.ago)

      expected = { version.id => 0 }

      assert_equal expected, Registry::PackageVersion.thirty_day_download_counts_for_ids(version.id)
    end
  end

  context "download stats" do
    test "normalizes downloads count by file count" do
      version = create(:registry_package_version, package: @package)
      version.files.build(size: 40, state: 1, filename: "test.jar", sha1: "abcdef", md5: "foobar")
      version.files.build(size: 60, state: 1, filename: "test2.jar", sha1: "abcdef", md5: "foobaz")
      version.save!

      assert_equal 3, version.files.count

      Timecop.freeze do
        3.times { Registry::PackageDownloadActivity.track(@package.id, version.id, Time.now) }
      end

      assert_equal 1, version.downloads_today
      assert_equal 1, version.downloads_last_thirty_days
      assert_equal 1, version.downloads_this_week
      assert_equal 1, version.downloads_this_month
      assert_equal 1, version.downloads_this_year
      assert_equal 1, version.downloads_total_count
    end

    test "counts partial downloads as a download" do
      partial_download_version = create(:registry_package_version, package: @package)

      Timecop.freeze do
        Registry::PackageDownloadActivity.track(@package.id, partial_download_version.id, Time.now)
      end

      assert_equal 1, partial_download_version.downloads_today
      assert_equal 1, partial_download_version.downloads_last_thirty_days
      assert_equal 1, partial_download_version.downloads_this_week
      assert_equal 1, partial_download_version.downloads_this_month
      assert_equal 1, partial_download_version.downloads_this_year
      assert_equal 1, partial_download_version.downloads_total_count
    end

    test "returns 0 when version has no downloads" do
      no_downloads_version = create(:registry_package_version, package: @package)

      assert_equal 0, no_downloads_version.downloads_today
      assert_equal 0, no_downloads_version.downloads_last_thirty_days
      assert_equal 0, no_downloads_version.downloads_this_week
      assert_equal 0, no_downloads_version.downloads_this_month
      assert_equal 0, no_downloads_version.downloads_this_year
      assert_equal 0, no_downloads_version.downloads_total_count
    end

    test "returns 0 when version has no files" do
      package = Registry::Package.new(
        name: "i-have-no-files",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )
      no_files_version = package.package_versions.build(
        version: "1.0.1",
        author: @user1,
        platform: "amd64",
        sha256: "this-is-not-a-real-sha256",
      )
      package.save!

      assert_equal 0, no_files_version.reload.files_count

      # Does not throw NaN errors with 0 downloads, 0 files
      assert_equal 0, no_files_version.downloads_today
      assert_equal 0, no_files_version.downloads_last_thirty_days
      assert_equal 0, no_files_version.downloads_this_week
      assert_equal 0, no_files_version.downloads_this_month
      assert_equal 0, no_files_version.downloads_this_year
      assert_equal 0, no_files_version.downloads_total_count

      Registry::PackageDownloadActivity.track(package.id, no_files_version.id, Time.now)

      # Does not throw Infinity errors with 1 download, 0 files
      assert_equal 0, no_files_version.downloads_today
      assert_equal 0, no_files_version.downloads_last_thirty_days
      assert_equal 0, no_files_version.downloads_this_week
      assert_equal 0, no_files_version.downloads_this_month
      assert_equal 0, no_files_version.downloads_this_year
      assert_equal 0, no_files_version.downloads_total_count
    end

    context ".downloads_last_thirty_days" do
      test "does not count downloads from over 30 days ago" do
        version = create(:registry_package_version, package: @package)

        Registry::PackageDownloadActivity.track(@package.id, version.id, 35.days.ago)

        assert_equal 0, version.downloads_last_thirty_days
      end
    end

    context ".total_download_count" do
      test "returns total sum of downloads" do
        version = create(:registry_package_version, package: @package)

        Registry::PackageDownloadActivity.track(@package.id, version.id, 60.days.ago)
        Registry::PackageDownloadActivity.track(@package.id, version.id, 35.days.ago)
        Registry::PackageDownloadActivity.track(@package.id, version.id, 20.days.ago)
        Registry::PackageDownloadActivity.track(@package.id, version.id, 2.days.ago)

        assert_equal 4, version.total_download_count
      end
    end
  end
end
