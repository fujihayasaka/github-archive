# typed: true
# frozen_string_literal: true
require "test_helper"

module PackageRegistry
  class PackageTest < GitHub::TestCase
    ACTION_PACKAGE_CLIENT = ::PackageRegistry::Twirp::ActionPackages::Client
    TagMock = Struct.new(
      :id,
      :display_login,
      :author_id,
      :package_id,
      :repo_id,
      :blob_store,
      :containerMetadata,
      :description,
      :digest,
      :ecosystem,
      :name,
      :namespace,
      :visibility,
      :created_at,
      :updated_at,
    )
    ContainerMetadataMock = Struct.new(:manifest, :tags, :labels)
    LabelsMock = Struct.new(:source)
    fixtures do
      @user = create(:user)
      @org = create(:organization)
      @org.add_member(@user)
    end

    setup do
      @timey_object = stub(nanos: 1000000, seconds: 10)
      @package = stub(created_at: @timey_object, updated_at: @timey_object, deleted_at: @timey_object, repo_id: nil, migrated_at: @timey_object, ecosystem: :container)
      @subject = Package.new(@package)
      @subject.latest_version = PackageVersion.new(stub(ecosystem: :container, containerMetadata: nil))

      @repo = create :repository, from_example: :repository_test_simple
    end

    test "#visibility" do
      package = stub(visibility: :PRIVATE)
      subject = Package.new(package)

      assert_equal "private", subject.visibility
    end

    context "#owner" do
      test "returns User owner by login" do
        package = stub(id: 12, namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        assert_equal @user, subject.owner
      end

      test "returns Org owner by login" do
        package = stub(id: 12, namespace: @org.login, owner_id: @org.id)
        subject = Package.new(package)

        assert_equal @org, subject.owner
      end
    end

    context "#owner_id=" do
      test "allows overriding the owner by id" do
        package = stub(id: 12, namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        subject.owner_id = @org.id
        assert_equal @org, subject.owner
      end
    end

    context "#author" do
      test "returns scoped installation when author type is SCOPED_INSTALLATION" do
        scoped_installation_id = 123
        package = stub(id: 12, author_id: scoped_installation_id, author_type: :SCOPED_INSTALLATION)
        scoped_installation = stub(id: scoped_installation_id)
        subject = Package.new(package)
        ScopedIntegrationInstallation.expects(:find_by_id).with(scoped_installation_id).returns(scoped_installation)

        assert_equal scoped_installation, subject.author
      end

      test "returns user when author type is USER" do
        package = stub(id: 12, author_id: @user.id, author_type: :USER)
        subject = Package.new(package)

        assert_equal @user, subject.author
      end
    end

    context "#public?" do
      test "returns false when visibility is private" do
        package = stub(visibility: :PRIVATE)
        subject = Package.new(package)

        refute subject.public?
      end

      test "returns false when visibility is internal" do
        package = stub(visibility: :INTERNAL)
        subject = Package.new(package)

        refute subject.public?
      end

      test "returns true when visibility is public" do
        package = stub(visibility: :PUBLIC)
        subject = Package.new(package)

        assert subject.public?
      end
    end

    test "#created_at" do
      assert_equal Time.at(10, 1000), @subject.created_at
    end

    test "#updated_at" do
      assert_equal Time.at(10, 1000), @subject.updated_at
    end

    test "deleted_at" do
      assert_equal Time.at(10, 1000), @subject.deleted_at
    end

    test "migrated_at" do
      assert_equal Time.at(10, 1000), @subject.migrated_at
    end

    context "#can_be_deleted?" do
      test "is true if private" do
        package = stub(visibility: :PRIVATE, namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        assert subject.can_be_deleted?
      end

      test "is true if internal" do
        package = stub(visibility: :INTERNAL, namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        assert subject.can_be_deleted?
      end

      test "is true if public" do
        package = stub(visibility: :PUBLIC, namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        assert subject.can_be_deleted?
      end
    end

    context "#members_can_publish_public_packages?" do
      test "for a user, it should be true by default" do
        package = stub(namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        assert subject.members_can_publish_public_packages?
      end

      test "for a user, it should be true regardless of org permissions" do
        package = stub(namespace: @user.login, owner_id: @user.id)
        subject = Package.new(package)

        @org.block_members_from_publishing_public_packages(actor: @user)

        assert subject.members_can_publish_public_packages?
      end

      test "for an org, it should be false by default" do
        package = stub(namespace: @org.login, owner_id: @org.id)
        subject = Package.new(package)

        refute subject.members_can_publish_public_packages?
      end

      test "for an org, it should be true when the permission is turned on" do
        package = stub(namespace: @org.login, owner_id: @org.id)
        subject = Package.new(package)

        @org.allow_members_to_publish_public_packages(force: true, actor: @user)

        assert subject.members_can_publish_public_packages?
      end
    end

    context "#members_can_publish_internal_packages?" do
      test "for a user, it should be false by default" do
        package = stub(owner_id: @user.id, namespace: @user.display_login)
        subject = Package.new(package)

        refute subject.members_can_publish_internal_packages?
      end

      test "for a user, it should be false regardless of org permissions" do
        package = stub(owner_id: @user.id, namespace: @user.display_login)
        subject = Package.new(package)

        @org.block_members_from_publishing_internal_packages(actor: @user)

        refute subject.members_can_publish_internal_packages?
      end

      test "for an org, it should be false by default" do
        package = stub(owner_id: @org.id, namespace: @org.display_login)
        subject = Package.new(package)

        refute subject.members_can_publish_internal_packages?
      end

      test "for an org, it should be true when the permission is turned on" do
        package = stub(owner_id: @org.id, namespace: @org.login)
        subject = Package.new(package)

        @org.allow_members_to_publish_internal_packages(force: true, actor: @user)

        assert subject.members_can_publish_internal_packages?
      end
    end

    context "docker container" do
      context "#dockerfile_url" do
        test "parses github url correctly" do
          dockerfile_url = "https://github.com/github/github/blob/master/DOCKERFILE"
          subject = Package.new(stub)
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: dockerfile_url
              )
            )
          ))

          assert_equal dockerfile_url, subject.dockerfile_url
        end

        test "parses non-github url correctly" do
          dockerfile_url = "https://foobar.com/test/alpine/-/tree/master/DOCKERFILE"
          subject = Package.new(stub)
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: dockerfile_url
              )
            )
          ))

          assert_equal dockerfile_url, subject.dockerfile_url
        end

        test "nil if label not present" do
          assert_nil @subject.dockerfile_url
        end
      end

      context "#repository" do
        test "returns a Repository object when github repo" do
          repository_url = "https://github.com/#{@repo.name_with_owner}"
          subject = Package.new(stub(repo_id: @repo.id))
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: repository_url
              )
            )
          ))

          assert_equal repository_url, subject.linked_repo_url
          assert_equal @repo, subject.repository
          assert_equal @repo.name_with_owner, subject.repository_name_with_owner
        end

        test "returns nil object when non-github repo" do
          repository_url = "https://foobar.com/test/alpine"
          subject = Package.new(stub(repo_id: nil, ecosystem: :container))
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: repository_url
              )
            )
          ))

          assert_equal repository_url, subject.linked_repo_url
          assert_nil subject.repository
          assert_equal "test/alpine", subject.repository_name_with_owner
        end

        test "returns nil when repository url is nil" do
          assert_nil @subject.linked_repo_url
          assert_nil @subject.repository
          assert_nil @subject.repository_name_with_owner
        end
      end

      context "#repository_name_with_owner" do
        test "nil when container has no image_url label" do
          subject = Package.new(stub(repo_id: nil, ecosystem: :container))
          assert_nil subject.linked_repo_url
          assert_nil subject.repository_name_with_owner
        end

        test "for a github repo" do
          repository_url = "https://github.com/#{@repo.name_with_owner}"
          subject = Package.new(TagMock.new(
            repo_id: @repo.id
          ))
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: repository_url
              )
            )
          ))

          assert_equal repository_url, subject.linked_repo_url
          assert_equal @repo.name_with_owner, subject.repository_name_with_owner
        end

        test "parses non-github url to find repository name" do
          repository_url = "foobar.com/test/alpine"
          subject = Package.new(stub(repo_id: nil, ecosystem: :container))
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: repository_url
              )
            )
          ))

          assert_equal repository_url, subject.linked_repo_url
          assert_equal "test/alpine", subject.repository_name_with_owner

          repository_url = "https://foobar.edu/test/alpine-docker"
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: repository_url
              )
            )
          ))

          assert_equal repository_url, subject.linked_repo_url
          assert_equal "test/alpine-docker", subject.repository_name_with_owner

          repository_url = "http://foobar.co.in/test/alpine"
          subject.latest_version = PackageVersion.new(TagMock.new(
            ecosystem: :container,
            containerMetadata: ContainerMetadataMock.new(
              labels: LabelsMock.new(
                source: repository_url
              )
            )
          ))

          assert_equal repository_url, subject.linked_repo_url
          assert_equal "test/alpine", subject.repository_name_with_owner
        end
      end
    end

    context "#target_for_conditional_access" do
      test "is an org for org-owned packages" do
        org = create(:organization)
        package = PackageRegistry::Package.new(TagMock.new(
          author_id: create(:user).id,
          ecosystem: :CONTAINER,
          id: 2,
          namespace: org.login,
          name: "foo",
          display_login: org.display_login
        ))

        assert_equal org, package.target_for_conditional_access
      end

      test "is a user for user-owned packages" do
        user = create(:user)
        package = PackageRegistry::Package.new(TagMock.new(
          author_id: user.id,
          ecosystem: :CONTAINER,
          id: 2,
          namespace: user.login,
          name: "foo",
          display_login: user.display_login
        ))

        assert_equal user, package.target_for_conditional_access
      end
    end

    context "#is_actions_package" do
      test "is_actions_package? false when not set" do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)
        assert_equal false, subject.is_actions_package?(@user)
      end

      test "is_actions_package? true when set and FF is on", feature_enabled: :view_immutable_actions do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert subject.is_actions_package?(@user)
      end

      test "is_actions_package? false when set and FF is off", feature_disabled: :view_immutable_actions do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert_equal false, subject.is_actions_package?(@user)
      end

      test "is_actions_package? false for non-containers, even if set" do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :MAVEN)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert_equal false, subject.is_actions_package?(@user)
      end
    end

    context "#can_edit_actions_package_sharing_policy?" do
      test "non-actions packages never show policy sharing settings" do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, visibility: :PRIVATE, owner_id: @user.id, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)
        assert_equal false, subject.can_edit_actions_package_sharing_policy?(@user)
      end

      test "public actions packages never show policy sharing settings" do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, visibility: :PUBLIC, owner_id: @user.id, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert_equal false, subject.can_edit_actions_package_sharing_policy?(@user)
      end

      test "private actions packages show policy sharing settings when FF is On", feature_enabled: :view_immutable_actions do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, visibility: :PRIVATE, owner_id: @user.id, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert_equal true, subject.can_edit_actions_package_sharing_policy?(@user)
      end

      test "private actions packages never show policy sharing settings when FF is Off", feature_disabled: :view_immutable_actions do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, visibility: :PRIVATE, owner_id: @user.id, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert_equal false, subject.can_edit_actions_package_sharing_policy?(@user)
      end

      test "internal actions packages show policy sharing settings when FF is On", feature_enabled: :view_immutable_actions do
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, visibility: :INTERNAL, owner_id: @user.id, ecosystem: :CONTAINER)
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: true))
        assert_equal true, subject.can_edit_actions_package_sharing_policy?(@user)
      end
    end

    context "#can_activate_actions_package?" do
      test "is false if serve_immutable_actions disabled" do
        GitHub.flipper[:serve_immutable_actions].disable
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER, owner_id: @org.id, namespace: @org.login, name: "foo")
        subject = Package.new(package)

        refute subject.can_activate_actions_package?(@user)
      end

      test "is false if view_immutable_actions disabled" do
        GitHub.flipper[:view_immutable_actions].disable

        GitHub.flipper[:serve_immutable_actions].enable
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER, owner_id: @org.id, namespace: @org.login, name: "foo")
        subject = Package.new(package)

        refute subject.can_activate_actions_package?(@user)
      end

      test "is false if is_actions_package not set" do
        GitHub.flipper[:view_immutable_actions].enable

        GitHub.flipper[:serve_immutable_actions].enable
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER, owner_id: @org.id, namespace: @org.login, name: "foo")
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance
          .stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id)
          .returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(is_action_package: false))

        refute subject.can_activate_actions_package?(@user)
      end

      test "is false if package is already activated" do
        GitHub.flipper[:view_immutable_actions].enable

        GitHub.flipper[:serve_immutable_actions].enable
        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER, owner_id: @org.id, namespace: @org.login, name: "foo")
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance
          .stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id)
          .returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(
            is_action_package: true,
            settings: {
              activated: true
            }
          ))

        refute subject.can_activate_actions_package?(@user)
      end

      test "is true if view_immutable_actions enabled && serve_immutable_actions enabled for owner and not already activated" do
        GitHub.flipper[:view_immutable_actions].enable

        GitHub.flipper[:serve_immutable_actions].enable(@org)

        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER, owner_id: @org.id, namespace: @org.login, name: "foo")
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance
          .stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id)
          .returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(
            is_action_package: true,
            settings: {
              activated: false
            }
          ))

        assert subject.can_activate_actions_package?(@user)
      end

      test "is true if view_immutable_actions enabled && serve_immutable_actions enabled for repo matching the NWO and not already activated" do
        GitHub.flipper[:view_immutable_actions].enable

        repo = create(:repository, owner: @org, name: "foo", from_example: :simple)

        GitHub.flipper[:serve_immutable_actions].enable(repo)

        package = Proto::RegistryMetadata::V1::Package::Package.new(id: 12, ecosystem: :CONTAINER, owner_id: @org.id, namespace: @org.login, name: "foo")
        subject = Package.new(package)
        ACTION_PACKAGE_CLIENT.any_instance
          .stubs(:get_action_package_resolution_settings)
          .with(package_id: package.id)
          .returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new(
            is_action_package: true,
            settings: {
              activated: false
            }
          ))

        assert subject.can_activate_actions_package?(@user)
      end
    end

    test "#sharing_policy_value" do
      assert_equal ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_ACCESSIBLE_SAME_BUSINESS, @subject.sharing_policy_value("Sharing_POLICY_ACCESSIBLE_SAME_BUSINESS")
      assert_equal ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_ACCESSIBLE_SAME_ORG, @subject.sharing_policy_value("Sharing_POLICY_ACCESSIBLE_SAME_ORG")
      assert_equal ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_ACCESSIBLE_SAME_USER, @subject.sharing_policy_value("Sharing_POLICY_ACCESSIBLE_SAME_USER")
      assert_equal ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_NONE, @subject.sharing_policy_value("Sharing_POLICY_NONE")

      assert_equal ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_UNKNOWN, @subject.sharing_policy_value("SHARING_POLICY_UNKNOWN")
      assert_equal ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_UNKNOWN, @subject.sharing_policy_value("This is just a random string")
    end
  end
end
