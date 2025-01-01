# typed: true
# frozen_string_literal: true

require "test_helper"
require "proto-registry-metadata-api"

module PackageRegistry
  module Twirp
    class MetadataClientTest < GitHub::TestCase
      CONTAINER_ECOSYSTEM = ::Proto::RegistryMetadata::V1::Package::Ecosystem::CONTAINER
      NPM_ECOSYSTEM = ::Proto::RegistryMetadata::V1::Package::Ecosystem::NPM
      SOFT_DELETE_MODE = ::Proto::RegistryMetadata::V1::Package::DeleteMode::SOFT
      PERMANENT_DELETE_MODE = ::Proto::RegistryMetadata::V1::Package::DeleteMode::PERMANENT

      ANY_SUBTYPE = ::Proto::RegistryMetadata::V1::Package::PackageSubtype::ANY

      PUBLIC_VISIBILITY = ::Proto::RegistryMetadata::V1::Package::Visibility::PUBLIC
      PRIVATE_VISIBILITY = ::Proto::RegistryMetadata::V1::Package::Visibility::PRIVATE

      USER_ACTOR = ::Proto::RegistryMetadata::V1::Package::ActorType::USER
      INSTALLATION_ACTOR = ::Proto::RegistryMetadata::V1::Package::ActorType::INSTALLATION
      UNSPECIFIED_ACTOR = ::Proto::RegistryMetadata::V1::Package::ActorType::UNSPECIFIED
      SITE_SCOPED_INSTALLATION_ACTOR = ::Proto::RegistryMetadata::V1::Package::ActorType::SITE_SCOPED_INSTALLATION

      setup do
        @subject = MetadataClient.new
        @package = stub(created_at: @timey_object, updated_at: @timey_object, deleted_at: @timey_object, repo_id: nil, migrated_at: @timey_object)
        @packages = stub(packages: [stub(name: "foo", created_at: @timey_object, updated_at: @timey_object, deleted_at: @timey_object, repo_id: nil, migrated_at: @timey_object)])
        @user = create(:user)
        @repo = create(:repository, owner: @user)

        @integration_app = create(:integration)
        @integration_app_installation = make_integration_installation(integration: @integration_app, target: @user, permissions: { "contents" => :write })

        @actions_app = create(:launch_integration, default_permissions: { "contents" => :write })
        disable_feature_flag(:disabled_global_apps, @actions_app)
        @actions_app_site_scoped_installation = make_site_scoped_integration_installation(integration: @actions_app, repositories: [@repo], target: @user, permissions: { "contents" => :write })
        @actions_site_scoped_bot = Bot.find_by_token(@actions_app_site_scoped_installation.generate_token.last)

        @actions_app_scoped_installation = make_scoped_integration_installation(
          parent: make_integration_installation(integration: @actions_app, target: @user, permissions: { "contents" => :write }),
          repositories: [@repo], permissions: { "contents" => :write })
        @actions_scoped_bot = Bot.find_by_token(@actions_app_scoped_installation.generate_token.last)

        unless GitHub.enterprise?
          @codespaces_app = create(:codespaces_integration, default_permissions: { "packages" => :read, "metadata" => :read, "contents" => :read })
          disable_feature_flag(:disabled_global_apps, @codespaces_app)
          @codespaces_app_installation = make_site_scoped_integration_installation(integration: @codespaces_app, repositories: [@repo], target: @user, permissions: { "packages" => :read, "metadata" => :read, "contents" => :read })
          @codespaces_bot = Bot.find_by_token(@codespaces_app_installation.generate_token.last)
        end

        @files = stub(files: [stub(package_version_id: 2, filename: "file1.txt", guid: "1d2f3e4f5e6f7e8f9e0", size: 123)])
      end

      context "#get_packages_metadata" do
        test "returns empty results" do
          response = stub("packages metadata", packages_metadata: [])
          @subject.expects(:rpc).with(:GetPackagesMetadata, user_id: 0, actor_type: UNSPECIFIED_ACTOR, package_ids: [1, 2, 3], include_deleted: false, exclude_latest_version: false, include_version_count: false, integration_name: nil).returns(response)
          assert_equal([], @subject.get_packages_metadata(actor: nil, package_ids: [1, 2, 3]))
        end
      end

      context "#update_package_version_ecodata" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:UpdatePackageVersionEcodata, user_id: @user.id, actor_type: USER_ACTOR, version_id: 1, key: "foo", value: "bar").returns(response)
          @subject.update_package_version_ecodata(actor: @user, version_id: 1, key: "foo", value: "bar")
        end
      end

      context "#get_package_metadata" do
        test "success" do
          package_metadata = stub("package metadata", package: @package, versions: [], latest_version: stub, total_version_count: 100)
          response = stub("response", package_metadata: package_metadata)
          @subject.expects(:rpc).with(:GetPackageMetadata, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @user.id, actor_type: USER_ACTOR, version_offset: 0, version_limit: 0, containerVersionFilter: nil, include_deleted: false, include_download_count: false,  integration_name: nil).returns(response)
          @package.expects(:ecosystem).at_least_once.returns(:container)
          assert_equal(::PackageRegistry::PackageMetadata, @subject.get_package_metadata(ecosystem: :container, namespace: "foo", name: "foo", actor: @user).class)
        end
      end

      context "#get_package_version" do
        test "success with integration " do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetPackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", version_id: 1, name: "foo", user_id: @integration_app_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: nil).returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_package_version(ecosystem: :container, namespace: "foo", version_id: 1, name: "foo", actor: @integration_app_installation).class)
        end

        test "success with actions site scoped " do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetPackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", version_id: 1, name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_package_version(ecosystem: :container, namespace: "foo", version_id: 1, name: "foo", actor: @actions_site_scoped_bot).class)
        end

        test "success with actions scoped " do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetPackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", version_id: 1, name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_package_version(ecosystem: :container, namespace: "foo", version_id: 1, name: "foo", actor: @actions_scoped_bot).class)
        end

        test "success with codespaces ", skip_enterprise: true do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetPackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", version_id: 1, name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "codespaces").returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_package_version(ecosystem: :container, namespace: "foo", version_id: 1, name: "foo", actor: @codespaces_bot).class)
        end
      end

      context "#get_container_latest_version" do
        test "success with integration " do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetContainerLatestVersion, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo", user_id: @integration_app_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: nil).returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_container_latest_version(ecosystem: :container, namespace: "foo", name: "foo", actor: @integration_app_installation).class)
        end

        test "success with actions site scope" do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetContainerLatestVersion, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_container_latest_version(ecosystem: :container, namespace: "foo", name: "foo", actor: @actions_site_scoped_bot).class)
        end

        test "success with actions scope" do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetContainerLatestVersion, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_container_latest_version(ecosystem: :container, namespace: "foo", name: "foo", actor: @actions_scoped_bot).class)
        end

        test "success with codespaces", skip_enterprise: true do
          version = stub("version")
          response = stub("response", version: version)
          @subject.expects(:rpc).with(:GetContainerLatestVersion, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "codespaces").returns(response)
          assert_equal(::PackageRegistry::PackageVersion, @subject.get_container_latest_version(ecosystem: :container, namespace: "foo", name: "foo", actor: @codespaces_bot).class)
        end
      end

      context "#get_packages_by_original_name" do
        test "success with app_installation_id" do
          response = stub(packages: [@package])
          @subject.expects(:rpc).with(:GetPackagesByOriginalName, ecosystem: NPM_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @integration_app_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: nil).returns(response)
          assert_equal(::PackageRegistry::Package, @subject.get_packages_by_original_name(ecosystem: :npm, namespace: "foo", name: "foo", actor: @integration_app_installation).first.class)
        end

        test "success with user_id" do
          response = stub(packages: [@package])
          @subject.expects(:rpc).with(:GetPackagesByOriginalName, ecosystem: NPM_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @user.id, actor_type: USER_ACTOR, integration_name: nil).returns(response)
          assert_equal(::PackageRegistry::Package, @subject.get_packages_by_original_name(ecosystem: :npm, namespace: "foo", name: "foo", actor: @user).first.class)
        end

        test "success with actions site scope" do
          response = stub(packages: [@package])
          @subject.expects(:rpc).with(:GetPackagesByOriginalName, ecosystem: NPM_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          assert_equal(::PackageRegistry::Package, @subject.get_packages_by_original_name(ecosystem: :npm, namespace: "foo", name: "foo", actor: @actions_site_scoped_bot).first.class)
        end

        test "success with actions scope" do
          response = stub(packages: [@package])
          @subject.expects(:rpc).with(:GetPackagesByOriginalName, ecosystem: NPM_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          assert_equal(::PackageRegistry::Package, @subject.get_packages_by_original_name(ecosystem: :npm, namespace: "foo", name: "foo", actor: @actions_scoped_bot).first.class)
        end

        test "success with codespaces", skip_enterprise: true do
          response = stub(packages: [@package])
          @subject.expects(:rpc).with(:GetPackagesByOriginalName, ecosystem: NPM_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "codespaces").returns(response)
          assert_equal(::PackageRegistry::Package, @subject.get_packages_by_original_name(ecosystem: :npm, namespace: "foo", name: "foo", actor: @codespaces_bot).first.class)
        end
      end

      context "#get_packages_by_names" do
        test "success with user" do
          package_metadata = stub("package metadata", package: @package, versions: [], latest_version: stub, total_version_count: 100)
          response = stub(packages: [package_metadata])
          @subject.expects(:rpc).with(:GetPackagesByNames, ecosystem: CONTAINER_ECOSYSTEM, namespace: "github", package_names: ["foo"], user_id: @user.id, actor_type: USER_ACTOR, integration_name: nil).returns(response)
          @package.expects(:ecosystem).at_least_once.returns(:container)
          assert_equal(::PackageRegistry::PackageMetadata, @subject.get_packages_by_names(ecosystem: :container, namespace: "github", package_names: ["foo"], actor: @user).first.class)
        end

        test "success with actions site scope" do
          package_metadata = stub("package metadata", package: @package, versions: [], latest_version: stub, total_version_count: 100)
          response = stub(packages: [package_metadata])
          @subject.expects(:rpc).with(:GetPackagesByNames, ecosystem: CONTAINER_ECOSYSTEM, namespace: "github", package_names: ["foo"], user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          @package.expects(:ecosystem).at_least_once.returns(:container)
          assert_equal(::PackageRegistry::PackageMetadata, @subject.get_packages_by_names(ecosystem: :container, namespace: "github", package_names: ["foo"], actor: @actions_site_scoped_bot).first.class)
        end

        test "success with actions scope" do
          package_metadata = stub("package metadata", package: @package, versions: [], latest_version: stub, total_version_count: 100)
          response = stub(packages: [package_metadata])
          @subject.expects(:rpc).with(:GetPackagesByNames, ecosystem: CONTAINER_ECOSYSTEM, namespace: "github", package_names: ["foo"], user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, integration_name: "actions").returns(response)
          @package.expects(:ecosystem).at_least_once.returns(:container)
          assert_equal(::PackageRegistry::PackageMetadata, @subject.get_packages_by_names(ecosystem: :container, namespace: "github", package_names: ["foo"], actor: @actions_scoped_bot).first.class)
        end

        test "success with codespaces", skip_enterprise: true do
          package_metadata = stub("package metadata", package: @package, versions: [], latest_version: stub, total_version_count: 100)
          response = stub(packages: [package_metadata])
          @subject.expects(:rpc).with(:GetPackagesByNames, ecosystem: CONTAINER_ECOSYSTEM, namespace: "github", package_names: ["foo"], user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, integration_name: "codespaces").returns(response)
          @package.expects(:ecosystem).at_least_once.returns(:container)
          assert_equal(::PackageRegistry::PackageMetadata, @subject.get_packages_by_names(ecosystem: :container, namespace: "github", package_names: ["foo"], actor: @codespaces_bot).first.class)
        end
      end

      context "#update_package_visibility" do
        test "with public visibility" do
          response = stub
          @subject.expects(:rpc).with(:UpdatePackage, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo", visibility: PUBLIC_VISIBILITY, user_id: @user.id, actor_type: USER_ACTOR).returns(response)

          @subject.update_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", visibility: "public", actor: @user)
        end

        test "with private visibility" do
          response = stub
          @subject.expects(:rpc).with(:UpdatePackage, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo", visibility: PRIVATE_VISIBILITY, user_id: @integration_app_installation.id, actor_type: INSTALLATION_ACTOR).returns(response)

          @subject.update_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", visibility: "private", actor: @integration_app_installation)
        end
      end

      context "#delete_package" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @user.id, actor_type: USER_ACTOR, mode: SOFT_DELETE_MODE, staff_override: false, integration_name: nil).returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @user, mode: :SOFT)
        end

        test "success with actions site scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: SOFT_DELETE_MODE, staff_override: false, integration_name: "actions").returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_site_scoped_bot, mode: :SOFT)
        end

        test "success with actions scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, mode: SOFT_DELETE_MODE, staff_override: false, integration_name: "actions").returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_scoped_bot, mode: :SOFT)
        end

        test "success with codespaces", skip_enterprise: true do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: SOFT_DELETE_MODE, staff_override: false, integration_name: "codespaces").returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @codespaces_bot, mode: :SOFT)
        end
      end

      context "#permanently_delete_package" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @user.id, actor_type: USER_ACTOR, mode: PERMANENT_DELETE_MODE, staff_override: false, integration_name: nil).returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @user, mode: :PERMANENT)
        end

        test "success with actions site scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: PERMANENT_DELETE_MODE, staff_override: false, integration_name: "actions").returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_site_scoped_bot, mode: :PERMANENT)
        end

        test "success with actions scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, mode: PERMANENT_DELETE_MODE, staff_override: false, integration_name: "actions").returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_scoped_bot, mode: :PERMANENT)
        end

        test "success with codespaces", skip_enterprise: true do
          response = stub
          @subject.expects(:rpc).with(:DeletePackage, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: PERMANENT_DELETE_MODE, staff_override: false, integration_name: "codespaces").returns(response)

          @subject.delete_package(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @codespaces_bot, mode: :PERMANENT)
        end
      end

      context "#delete_package_version" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @user.id, actor_type: USER_ACTOR, mode: SOFT_DELETE_MODE, version: "latest", integration_name: nil).returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @user, mode: :SOFT, version: "latest")
        end

        test "success with actions site scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: SOFT_DELETE_MODE, version: "latest", integration_name: "actions").returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_site_scoped_bot, mode: :SOFT, version: "latest")
        end

        test "success with actions scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, mode: SOFT_DELETE_MODE, version: "latest", integration_name: "actions").returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_scoped_bot, mode: :SOFT, version: "latest")
        end

        test "success with codespaces", skip_enterprise: true do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: SOFT_DELETE_MODE, version: "latest", integration_name: "codespaces").returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @codespaces_bot, mode: :SOFT, version: "latest")
        end

        test "does not call failbot_report on permission_denied error" do
          error = stub(code: :permission_denied, msg: "Permission denied")
          response = stub(error: error)
          @subject.expects(:client).returns(stub(rpc: response))
          @subject.expects(:failbot_report).never

          assert_raises(PackageRegistry::Twirp::PermissionDeniedError) do
            @subject.rpc(:DeletePackageVersion, {})
          end
        end
      end

      context "#permanently_package_version" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @user.id, actor_type: USER_ACTOR, mode: PERMANENT_DELETE_MODE, version: "latest", integration_name: nil).returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @user, mode: :PERMANENT, version: "latest")
        end

        test "success with actions site scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_site_scoped_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: PERMANENT_DELETE_MODE, version: "latest", integration_name: "actions").returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_site_scoped_bot, mode: :PERMANENT, version: "latest")
        end

        test "success with actions scope" do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @actions_app_scoped_installation.id, actor_type: INSTALLATION_ACTOR, mode: PERMANENT_DELETE_MODE, version: "latest", integration_name: "actions").returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @actions_scoped_bot, mode: :PERMANENT, version: "latest")
        end

        test "success with codespaces", skip_enterprise: true do
          response = stub
          @subject.expects(:rpc).with(:DeletePackageVersion, ecosystem: CONTAINER_ECOSYSTEM, package_subtype: ANY_SUBTYPE, namespace: "foo", name: "foo", user_id: @codespaces_app_installation.id, actor_type: SITE_SCOPED_INSTALLATION_ACTOR, mode: PERMANENT_DELETE_MODE, version: "latest", integration_name: "codespaces").returns(response)

          @subject.delete_package_version(ecosystem: :CONTAINER, namespace: "foo", name: "foo", actor: @codespaces_bot, mode: :PERMANENT, version: "latest")
        end
      end

      context "#get_packages_by_repo" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:GetPackagesByRepo, repo_id: 2).returns(response)

          @subject.get_packages_by_repo(repo_id: 2)
        end
      end

      context "#get_package_visibility" do
        test "success" do
          response = stub
          @subject.expects(:rpc).with(:GetPackageVisibility, ecosystem: CONTAINER_ECOSYSTEM, namespace: "foo", name: "foo").returns(response)
          @subject.get_package_visibility(ecosystem: :CONTAINER, namespace: "foo", name: "foo")
        end
      end

      context "#get_package_version_files" do
        test "success" do
          @subject.expects(:rpc).with(:GetPackageVersionFiles, version_id: 1).returns(@files)

          @subject.get_package_version_files(version_id: 1)
        end
      end
    end
  end
end
