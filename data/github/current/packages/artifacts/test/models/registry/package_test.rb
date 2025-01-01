# typed: false
# frozen_string_literal: true

require "test_helper"

class RegistryPackageTest < GitHub::TestCase
  include GitHub::RegistryPackageHelper
  include HydroTestHelpers
  include Registry::PackageDownloadStatsService

  fixtures do
    @user = create(:user, plan: :pro)
    @repo = create(:private_repository, owner: @user, from_example: :repository_test_simple)
    @public_repo = create(:public_repository, owner: @user, from_example: :repository_test_simple)

    @package_owner = create(:user, plan: :pro)
    @package_repo = create(:private_repository, owner: @package_owner, from_example: :repository_test_simple)

    @package = Registry::Package.new(
      name: "foo-package",
      repository: @package_repo,
      owner: @package_repo.owner,
      package_type: :rubygems,
    )
    @package_version = @package.package_versions.build version: "1.0",
      author: @package_owner,
      platform: "amd64",
      sha256: "this-is-not-a-real-sha256"
    @package_version.metadata.build(name: Registry::Metadatum::KEYS[:README], value: "lorem dimsum")
    @package_version.files.build(size: 1, state: 1, filename: "hello.jar", sha1: "sha1", md5: "md5")

    @another_version = @package.package_versions.build version: "1.1",
      author: @package_owner,
      platform: "amd64",
      sha256: "still-not-a-real-sha256"
    @another_version.files.build(size: 40, state: 1, filename: "test.jar", sha1: "abcdef", md5: "foobar")
    @another_version.files.build(size: 60, state: 1, filename: "test2.jar", sha1: "abcdef", md5: "foobaz")

    @package.save!
  end

  context ".total_download_counts_for_ids" do
    test "returns correct counts" do
      # @package_version has 1 file so this counts as 3 downloads
      3.times { Registry::PackageDownloadActivity.track(@package.id, @package_version.id, Time.new(2019, 12, 3)) }
      # @another_version has 2 files so this counts as 1 download
      2.times { Registry::PackageDownloadActivity.track(@package.id, @another_version.id, Time.new(2019, 12, 3)) }

      expected = { @package.id => 4 }

      assert_equal expected, Registry::Package.total_download_counts_for_ids(@package.id)

      no_downloads_package = create(:registry_package, repository: @package_repo)

      expected = { no_downloads_package.id => 0 }

      assert_equal expected, Registry::Package.total_download_counts_for_ids(no_downloads_package.id)
    end

    test "returns empty hash when package is not found" do
      destroyed_package = create(:registry_package, repository: @package_repo)
      destroyed_package_id = destroyed_package.id
      destroyed_package.destroy

      assert_empty Registry::Package.total_download_counts_for_ids(destroyed_package_id)
    end

    test "does not count downloads of deleted versions" do
      package = create(:registry_package, repository: @package_repo)
      version = package.package_versions.first

      Registry::PackageDownloadActivity.track(package.id, version.id, Time.new(2019, 12, 3))

      version.delete!

      expected = { package.id => 0 }

      assert_equal expected, Registry::Package.total_download_counts_for_ids(package.id)
    end

    test "defaults to 0 when package version is missing" do
      package = create(:registry_package, repository: @package_repo)
      version = create(:registry_package_version, package: package)
      destroyed_version_id = version.id
      version.destroy

      Registry::PackageDownloadActivity.track(package.id, destroyed_version_id, Time.now)

      expected = { package.id => 0 }

      assert_equal expected, Registry::Package.total_download_counts_for_ids(package.id)
    end
  end

  context ".thirty_day_download_counts_for_ids" do
    test "returns correct counts" do
      # @package_version has 1 file so this counts as 3 downloads
      3.times { Registry::PackageDownloadActivity.track(@package.id, @package_version.id, Time.now) }
      # @another_version has 2 files so this counts as 1 download
      2.times { Registry::PackageDownloadActivity.track(@package.id, @another_version.id, Time.now) }

      expected = { @package.id => 4 }

      assert_equal expected, Registry::Package.thirty_day_download_counts_for_ids(@package.id)
    end

    test "does not count downloads from over 30 days ago" do
      package = create(:registry_package, repository: @package_repo)

      Registry::PackageDownloadActivity.track(package.id, package.package_versions.first.id, 35.days.ago)

      expected = { package.id => 0 }

      assert_equal expected, Registry::Package.thirty_day_download_counts_for_ids(package.id)
    end

    test "returns empty hash when package is not found" do
      destroyed_package = create(:registry_package, repository: @package_repo)
      destroyed_package_id = destroyed_package.id
      destroyed_package.destroy

      assert_empty Registry::Package.thirty_day_download_counts_for_ids(destroyed_package_id)
    end

    test "does not count downloads of deleted versions" do
      package = create(:registry_package, repository: @package_repo)
      version = package.package_versions.first

      Registry::PackageDownloadActivity.track(package.id, version.id, Time.now)

      version.delete!

      expected = { package.id => 0 }

      assert_equal expected, Registry::Package.thirty_day_download_counts_for_ids(package.id)
    end

    test "defaults to 0 when package version is missing" do
      package = create(:registry_package, repository: @package_repo)
      version = create(:registry_package_version, package: package)
      destroyed_version_id = version.id
      version.destroy

      Registry::PackageDownloadActivity.track(package.id, destroyed_version_id, Time.now)

      expected = { package.id => 0 }

      assert_equal expected, Registry::Package.thirty_day_download_counts_for_ids(package.id)
    end
  end

  test ".private_scope and .public_scope return private and public packages respectively" do
    public_repo = create :repository, owner: @package_owner, from_example: :repository_test_simple
    public_package = create(:registry_package, repository: public_repo)

    private_repo = create :private_repository, owner: @package_owner, from_example: :repository_test_simple
    private_package = create(:registry_package, repository: private_repo)

    assert_includes Registry::Package.private_scope.to_a, private_package
    refute_includes Registry::Package.private_scope.to_a, public_package

    refute_includes Registry::Package.public_scope.to_a, private_package
    assert_includes Registry::Package.public_scope.to_a, public_package
  end

  context ".with_active_versions" do
    test "only returns packages with an active version" do
      foo = create(:registry_package, repository: @package_repo)
      latest_version = foo.package_versions.last
      latest_version.delete!
      refute foo.reload.active?

      assert_raises ActiveRecord::RecordNotFound do
        Registry::Package.with_active_versions.find(foo.id)
      end
    end

    test "returns distinct results" do
      foo = create(:registry_package, repository: @package_repo)
      create(:registry_package_version, package: foo)
      assert_equal 2, foo.package_versions.count

      active_packages = Registry::Package.with_active_versions.to_a
      assert_same_elements active_packages.uniq, active_packages
    end
  end

  context "name normalization during validation" do
    test "whitespace is stripped and condensed" do
      package = Registry::Package.new(name: "package name", repository: @repo)
      package.valid?
      assert_equal "package name", package.name

      package = Registry::Package.new(name: "package  name", repository: @repo)
      package.valid?
      assert_equal "package name", package.name

      package = Registry::Package.new(name: " package  name", repository: @repo)
      package.valid?
      assert_equal "package name", package.name

      package = Registry::Package.new(name: " package  name  ", repository: @repo)
      package.valid?
      assert_equal "package name", package.name

      # Unicode whitespace and Unicode looks-like-whitespace-but-technically-isn't.
      package = Registry::Package.new(name: " package \u00A0name\u200B", repository: @repo)
      package.valid?
      assert_equal "package name", package.name
    end
  end

  context "symbolize_package_type" do
    test "symbolizes a valid string package type" do
      assert_equal :npm, Registry::Package.symbolize_package_type("npm")
    end

    test "does not symbolize an invalid string package type" do
      refute_equal :invalid, Registry::Package.symbolize_package_type("invalid")
    end
  end

  context "#latest_version" do
    test "returns version tagged 'latest' if one exists" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )

      Timecop.freeze(Date.parse "2017-10-01") do
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

      Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      Registry::Tag.create!(name: "latest", registry_package_version_id: v2.id, registry_package_id: package.id)

      assert_equal v2, package.latest_version
    end

    test "returns most recent version if version tagged 'latest' is deleted" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )

      Timecop.freeze(Date.parse "2017-10-01") do
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

      v2.delete!

      assert_equal v1dot1, package.latest_version
    end

    test "returns most recent non-deleted version if none tagged 'latest'" do
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

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      v1dot1.delete!

      assert_equal v1, package.latest_version
    end
  end

  context "#version_by_version_string" do
    test "returns the associated version" do
      assert_equal @package_version, @package.version_by_version_string("1.0")
    end

    test "respects includeDeleted parameter" do
      @package_version.delete!

      assert_nil @package.version_by_version_string("1.0")
      assert_equal @package_version, @package.package_versions.find_by(original_name: "1.0")

      @package_version.deleted_at = nil
      @package_version.save!
    end
  end

  context "#version_by_sha256" do
    test "returns the associated version" do
      assert_equal @package_version, @package.version_by_sha256("this-is-not-a-real-sha256")
    end

    test "respects includes_deleted parameter" do
      @package_version.delete!

      assert_nil @package.version_by_sha256("this-is-not-a-real-sha256")
      assert_equal @package_version, @package.version_by_sha256("this-is-not-a-real-sha256", include_deleted: true)

      @package_version.deleted_at = nil
      @package_version.save!
    end
  end

  context "#version_by_platform" do
    test "returns the associated version" do
      assert_equal @package_version, @package.version_by_platform("1.0", "amd64")
    end

    test "respects includes_deleted parameter" do
      @package_version.delete!

      assert_nil @package.version_by_platform("1.0", "amd64")
      assert_equal @package_version, @package.package_versions.find_by(original_name: "1.0", platform: "amd64")

      @package_version.deleted_at = nil
      @package_version.save!
    end
  end

  context "#source_registry" do
    Registry::Package::PUBLICLY_SUPPORTED_TYPES.each do |type|
      test "#{type}" do
        package = build(:registry_package, repository: @repo, registry_package_type: type)

        uri = case type
        when :npm
          "@#{package.owner.login}"
        when :docker
          "#{package.owner.login}/#{package.repository.name}"
        else
          package.owner.login
        end

        expected = {
          about_url: "#{GitHub.help_url}/packages/learn-github-packages/introduction-to-github-packages",
          name: "GitHub #{type} registry",
          type: type.to_s,
          url: "#{GitHub.urls.registry_url(type)}#{uri}",
          vendor: "GitHub Inc",
        }
        assert_equal(expected, package.source_registry)
      end
    end
  end

  context "search index" do
    test "is sync'd when a package is created" do
      # A new release is created in the package factory, which is also indexed so we need to account for it
      Search.expects(:add_to_search_index).with("release", instance_of(Integer))

      Search.expects(:add_to_search_index).with("registry_package", instance_of(Integer)).at_least_once

      create :registry_package, repository: @repo
    end

    test "caches are updated when package counts change" do
      reset_cache
      with_cache_enabled do
        pkg1 = create :registry_package, repository: @repo
        create :registry_package_version, package: pkg1
        last_update = (@repo.packages.order(updated_at: :desc).first.updated_at.to_f * 1000.00).to_i
        cache_key1 = "repository:packages:count:#{@repo.id}:#{last_update}"
        count = @repo.packages.joins(:package_versions).merge(Registry::PackageVersion.not_deleted).distinct.count
        GitHub.cache.set(cache_key1, count)
        assert_equal 1, GitHub.cache.get(cache_key1)
        cache_key2 = ""

        # jcvd says if we don't change the time we get the same cache key name
        Timecop.freeze(Date.today + 2) do
          pkg2 = create :registry_package, repository: @repo
          create :registry_package_version, package: pkg2
          last_update = (@repo.packages.order(updated_at: :desc).first.updated_at.to_f * 1000.00).to_i
          cache_key2 = "repository:packages:count:#{@repo.id}:#{last_update}"
          count = @repo.packages.joins(:package_versions).merge(Registry::PackageVersion.not_deleted).distinct.count
          GitHub.cache.set(cache_key2, count)
          assert_equal 2, GitHub.cache.get(cache_key2)
          assert_equal 1, GitHub.cache.get(cache_key1)
        end

        Timecop.freeze(Date.today + 4) do
          pkg1.delete!
          last_update = (@repo.packages.order(updated_at: :desc).first.updated_at.to_f * 1000.00).to_i
          cache_key3 = "repository:packages:count:#{@repo.id}:#{last_update}"
          count = @repo.packages.joins(:package_versions).merge(Registry::PackageVersion.not_deleted).distinct.count
          GitHub.cache.set(cache_key3, count)
          assert_equal 1, GitHub.cache.get(cache_key3)
          assert_equal 2, GitHub.cache.get(cache_key2)
          assert_equal 1, GitHub.cache.get(cache_key1)
        end

      end
    end

    test "is sync'd when a package is updated" do
      package = create :registry_package, repository: @repo

      Search.expects(:add_to_search_index).with("registry_package", package.id)
      package.update! name: "new-name"
    end

    test "is sync'd when a package is deleted" do
      package = create :registry_package, repository: @repo

      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["registry_package", package.id, @repo.id] do
        package.destroy
      end
    end

    test "is sync'd when a package version is created" do
      package = create :registry_package, repository: @repo

      # A new release is created in the package factory, which is also indexed so we need to account for it
      Search.expects(:add_to_search_index).with("release", instance_of(Integer))
      Search.expects(:add_to_search_index).with("registry_package", package.id)

      create :registry_package_version, package: package
    end

    test "is sync'd when a package version is updated" do
      package = create :registry_package, repository: @repo

      Search.expects(:add_to_search_index).with("registry_package", package.id)

      version = package.package_versions.first
      version.update! version: "v1.update"
    end

    test "is sync'd when a package version is deleted" do
      package = create :registry_package, repository: @repo
      version = create :registry_package_version, package: package

      Search.expects(:add_to_search_index).with("registry_package", package.id)
      version.destroy
    end

    test "is sync'd when downloads are counted" do
      package = create :registry_package, repository: @repo

      Search.expects(:add_to_search_index).with("registry_package", package.id, interval: 60)

      Registry::PackageDownloadActivity.track(package.id, package.package_versions.first.id, Time.now.beginning_of_hour)
    end

    test "is sync'd when the repo has a topic applied" do
      package = create :registry_package, repository: @repo

      Search.expects(:add_to_search_index).with("registry_package", package.id)
      Search.stubs(:add_to_search_index).with(Not(equals("registry_package")), anything)

      topic = create(:topic, name: "ruby")
      topic.repository_topics.create!(repository: package.repository, state: :created, user: package.owner)
    end

    test "is sync'd when its repo is deleted" do
      package = create :registry_package, repository: @repo
      @repo.destroy

      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["registry_package", package.id, package.repository_id] do
        package.reload.touch
      end
    end

    test "is sync'd when a version is deleted" do
      package = create :registry_package, repository: @repo
      version1 = package.package_versions.first
      version2 = create :registry_package_version, package: package
      assert_equal 2, package.package_versions.reload.length

      Search.expects(:add_to_search_index).with("registry_package", package.id).times(3)
      version1.delete!
      version2.delete!
    end
  end

  context "#can_be_deleted?" do
    test "true when repository is public" do
      public_repo = create :repository, owner: @user, from_example: :repository_test_simple

      package = create :registry_package, repository: public_repo
      assert package.can_be_deleted?
    end

    test "true for private package" do
      package = create :registry_package, repository: @repo, package_type: :npm
      assert package.can_be_deleted?
    end
  end

  context "download stats" do
    test "zero when no downloads" do
      package = create(:registry_package, repository: @package_repo)

      assert_equal 0, package.downloads_today
      assert_equal 0, @package.downloads_this_week
      assert_equal 0, @package.downloads_this_month
      assert_equal 0, @package.downloads_this_year
      assert_equal 0, @package.downloads_total_count
    end

    test "normalizes downloads count by file count" do
      Timecop.freeze do
        @package.package_versions.each do |v|
          v.files.count.times { Registry::PackageDownloadActivity.track(@package.id, v.id, Time.now) }
        end
      end

      assert_equal 2, @package.downloads_today
      assert_equal 2, @package.downloads_this_week
      assert_equal 2, @package.downloads_this_month
      assert_equal 2, @package.downloads_this_year
      assert_equal 2, @package.downloads_total_count
    end

    test "defaults to 0 when package version has no files" do
      package_with_no_files = Registry::Package.new(
        name: "i-have-no-files",
        repository: @package_repo,
        owner: @package_repo.owner,
        package_type: :rubygems,
      )
      package_with_no_files.package_versions.build(
        version: "1.0.1",
        author: @package_owner,
        platform: "amd64",
        sha256: "this-is-not-a-real-sha256",
      )
      package_with_no_files.save!

      assert_equal 0, package_with_no_files.downloads_today
      assert_equal 0, package_with_no_files.downloads_this_week
      assert_equal 0, package_with_no_files.downloads_this_month
      assert_equal 0, package_with_no_files.downloads_this_year
      assert_equal 0, package_with_no_files.downloads_total_count
    end

    test "defaults to 0 when package version is missing" do
      package = create(:registry_package, repository: @package_repo)
      version = create(:registry_package_version, package: package)
      Registry::PackageDownloadActivity.track(package.id, version.id, Time.now)

      version.destroy

      assert_equal 0, package.downloads_today
      assert_equal 0, package.downloads_this_week
      assert_equal 0, package.downloads_this_month
      assert_equal 0, package.downloads_this_year
      assert_equal 0, package.downloads_total_count
    end

    test "does not count downloads of deleted versions" do
      package = create(:registry_package, repository: @package_repo)
      version = package.package_versions.first

      Registry::PackageDownloadActivity.track(package.id, version.id, Time.new(2019, 12, 3))

      version.delete!

      assert_equal 0, package.downloads_today
      assert_equal 0, package.downloads_this_week
      assert_equal 0, package.downloads_this_month
      assert_equal 0, package.downloads_this_year
      assert_equal 0, package.downloads_total_count
    end
  end

  context "package data by type" do
    test "gets ownership and package data by type" do
      package_data = Registry::Package.package_data_for_type("rubygems")
      assert_equal "rubygems", package_data.name
      assert_equal 1, package_data.total_pkgs_published_count
      assert_equal [@package_repo.owner], package_data.distinct_owners_to_enumerate
      assert_equal 1, package_data.distinct_owners_count
    end

    test "type translators returns correct types" do
      assert_equal "npm", Registry::Package.translate_package_id(0)
      assert_equal "RubyGems", Registry::Package.translate_package_id(1)
      assert_equal "Maven", Registry::Package.translate_package_id(2)
      assert_equal "Docker", Registry::Package.translate_package_id(3)
      assert_equal "Debian", Registry::Package.translate_package_id(4)
      assert_equal "NuGet", Registry::Package.translate_package_id(5)
      assert_equal [0, 1, 2, 3, 5], Registry::Package.supported_package_type_values
      assert_equal [:npm, :rubygems, :maven, :docker, :nuget], Registry::Package.enabled_types
    end
  end

  context "delete and restore" do
    test "can delete entire package" do
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

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      v1dot2 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.2")
        package.package_versions << version
        package.save
        version
      end

      package.delete!

      assert_equal 1, package.repository.packages.count
      assert_equal 0, package.repository.packages.where(deleted_at: nil).count
      assert_equal 0, package.package_versions.where(deleted_at: nil).count

      assert_hydro_messages(count: 3, schema: "package_registry.v0.PackageVersionDeleted")
      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageDeleted")
    end

    test "cannot delete public package that contains a version with more than #{PUBLIC_VERSION_DELETE_LIMIT} downloads" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @public_repo,
        owner: @public_repo.owner,
        package_type: :rubygems,
      )

      v1 = Timecop.freeze(Date.parse "2017-10-01") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1")
        package.package_versions << version
        package.save
        version
      end

      (PUBLIC_VERSION_DELETE_LIMIT + 1).times { Registry::PackageDownloadActivity.track(package.id, v1.id, Time.now) }

      assert_equal (PUBLIC_VERSION_DELETE_LIMIT + 1), v1.downloads_total_count

      assert_raises Registry::Package::PackageDeletionError do
        package.delete!
      end

      assert_equal 1, package.repository.packages.count
      assert_equal 1, package.repository.packages.where(deleted_at: nil).count
    end

    test "can restore entire package" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )

      v1 = Timecop.freeze(Date.parse "2017-10-01") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1")
        version.files << Registry::File.new(filename: "v1", size: 1)
        package.package_versions << version
        package.save
        version
      end

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        version.files << Registry::File.new(filename: "v1.1", size: 1)
        package.package_versions << version
        package.save
        version
      end

      v1dot2 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.2")
        version.files << Registry::File.new(filename: "v1.2", size: 1)
        package.package_versions << version
        package.save
        version
      end

      Timecop.freeze(Date.parse "2017-10-04") do
        package.delete!
        package.reload

        assert_equal 3, package.package_versions.deleted.count

        package.restore!
        assert_equal 3, package.package_versions.not_deleted.count

        assert_hydro_messages(count: 6, schema: "package_registry.v0.PackageFilePublished")
        assert_hydro_messages(count: 3, schema: "package_registry.v0.PackageVersionPublished")
        assert_hydro_messages(count: 1, schema: "package_registry.v0.PackagePublished")
      end
    end

    test "can restore package deleted by the legacy delete flow" do
      package = Registry::Package.new(
        name: "irrelevant-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :rubygems,
      )

      # at one time v1 packages could only be deleted by deleting every version individually
      # these packages should all restore with the last version to be deleted

      v1 = Timecop.freeze(Date.parse "2017-10-01") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1")
        version.files << Registry::File.new(filename: "v1", size: 1)
        package.package_versions << version
        package.save
        version
      end

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        version.files << Registry::File.new(filename: "v1.1", size: 1)
        package.package_versions << version
        version.delete!
        package.save
        version
      end

      Timecop.freeze(Date.parse "2017-10-04") do
        assert_equal 1, package.package_versions.deleted.count
        assert_equal 1, package.package_versions.not_deleted.count

        expected_version_name = package.package_versions.not_deleted.first.version

        package.package_versions.not_deleted.first.delete!
        package.reload

        assert package.deleted?
        assert_equal 2, package.package_versions.deleted.count

        assert_equal v1, package.package_versions.find_by(original_name: expected_version_name)

        package.restore!
        assert_equal 1, package.package_versions.not_deleted.count
        assert_equal expected_version_name, package.package_versions.not_deleted.first.version

        assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionPublished")
        assert_hydro_messages(count: 1, schema: "package_registry.v0.PackagePublished")
      end
    end

    test "only restores grouply deleted versions" do
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

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      v1dot2 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.2")
        package.package_versions << version
        package.save
        version
      end

      Timecop.freeze(Date.parse "2017-10-04") do
        v1dot1.delete!
      end

      Timecop.freeze(Date.parse "2017-10-05") do
        package.delete!
        package.reload
        package.restore!
        assert_equal 2, package.package_versions.not_deleted.count
        refute_equal "v1.1", package.package_versions.not_deleted.first.version
        refute_equal "v1.1", package.package_versions.not_deleted.second.version
      end
    end

    test "cannot restore expired packages" do
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

      v1dot1 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.1")
        package.package_versions << version
        package.save
        version
      end

      v1dot2 = Timecop.freeze(Date.parse "2017-10-03") do
        version = make_registry_package_version(registry_package: package, tag_name: "v1.2")
        package.package_versions << version
        package.save
        version
      end

      Timecop.freeze(Date.parse "2017-10-04") do
        package.delete!
      end

      package.reload

      Timecop.freeze(Date.parse "2017-11-10") do
        assert_raises Registry::Package::PackageDeletionError do
          package.restore!
        end
      end
    end
  end

  context "migrated?" do
    test "returns true if all of the package's versions have been migrated" do
      assert @package.package_versions.count > 0

      @package.package_versions.each do |version|
        version.update!(migration_state: :complete)
      end

      assert @package.migrated?
    end

    test "returns true if all of the package's versions have been migrated excluding versions deleted more than 30 days ago" do
      assert @package.package_versions.count == 2

      @package.package_versions.first.update!(migration_state: :complete)
      @package.package_versions.last.update!(migration_state: :unmigrated, deleted_at: Time.now.utc.ago(31.days))

      assert @package.migrated?
    end

    test "returns false if none of the package's versions have not been migrated" do
      assert @package.package_versions.count > 0
      refute @package.migrated?
    end

    test "returns false if any of the package's versions have not been migrated" do
      assert @package.package_versions.count > 1

      @package.package_versions.first.update!(migration_state: :complete)

      refute @package.migrated?
    end

    test "returns false if any of the package's versions migration state is pending" do
      assert @package.package_versions.count > 1
      @package.package_versions.first.update!(migration_state: :pending)
      refute @package.migrated?
    end
  end

  context "docker package count" do
    test "Any docker package should return the count greater then 1 if there are docker packages" do
      @docker_package = Registry::Package.new(
        name: "docker-package",
        repository: @package_repo,
        owner: @package_repo.owner,
        package_type: :docker,
        )

      @docker_package.save!

      assert_equal(1, Registry::Package.any_package_exists("docker").count, "count for docker package is not correct")
    end

    test "Any docker package should return 0 if there are no docker packages" do
      assert_equal(0, Registry::Package.any_package_exists("docker").count, "count for docker package is not correct")
    end
  end

end
