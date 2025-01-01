# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class PackagesTest < Api::SerializerTestCase

  PackageMetadataMock = Struct.new(:package, :latest_version, :versions, :total_version_count)
  PackageMock = Struct.new(
    :total_version_count,
    :id,
    :namespace,
    :name,
    :ecosystem,
    :created_at,
    :updated_at,
    :author_id,
    :visibility,
    :repo_id
  )
  TimeMock = Struct.new(:seconds, :nanos)

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, plan: "medium")
    @rando = create(:user)

    @org = create(:organization, admin: @user)
    @org_repo = create(:private_repository, owner: @org)

    @v1_package = Registry::Package.new(
      name: "private-org-package",
      repository: @org_repo,
      owner: @org,
      package_type: :npm,
    )

    @v1_package.save!

    @v1_package_docker = Registry::Package.create(
      name: "private-org-package",
      repository: @org_repo,
      owner: @org,
      package_type: :docker,
    )

    @v1_version = @v1_package_docker.package_versions.create(version: "1", author: @user)

    @v2_package = ::PackageRegistry::PackageMetadata.new(PackageMetadataMock.new(
      package: PackageMock.new(
        total_version_count: 1,
        id: 1,
        namespace: @org.login,
        name: "alpine",
        ecosystem: :container,
        created_at: TimeMock.new(seconds: 1599107251, nanos: 948286000),
        updated_at: TimeMock.new(seconds: 1599542839, nanos: 333573000),
        author_id: @user.id,
        visibility: :private,
        repo_id: @org_repo.id
      ),
      total_version_count: 1
    ))
  end

  context "#package_hash" do
    context "v1 package" do
      test "includes the repository with owner if associated" do
        wrapped = Api::Packages::PackageV1Adapter.new(@v1_package)
        output = package(wrapped, { current_user: @user })
        refute_nil output["repository"]
        refute_nil output["repository"]["owner"]
      end
    end

    context "v2 package" do
      test "includes the repository with owner if associated" do
        wrapped = Api::Packages::PackageV2Adapter.new(@v2_package)
        output = package(wrapped, { current_user: @user })
        refute_nil output["repository"]
        refute_nil output["repository"]["owner"]
      end

      test "doesnt includes the repository if current_user does not have access" do
        wrapped = Api::Packages::PackageV2Adapter.new(@v2_package)
        output = package(wrapped, { current_user: @rando })
        assert_nil output["repository"]
      end
    end
  end

  context "#package_version_hash" do
    context "v1 package version" do
      test "docker metadata" do
        wrapped_package = Api::Packages::PackageV1Adapter.new(@v1_package_docker)
        wrapped = Api::Packages::PackageVersionV1Adapter.new(wrapped_package, @v1_version)
        output = package_version(wrapped)
        refute_nil output["metadata"]["docker"]
      end
    end
  end
end
