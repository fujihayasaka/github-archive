# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryImageTest < GitHub::TestCase
  include HydroTestHelpers
  include UploadableTestHelpers
  include CdnTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @image = RepositoryImage.new(repository: @repo, uploader: @user)
    save_file_for_uploadable @image, name: "fancy-upload-of-mine.jpg"
  end

  teardown do
    GitHub.repository_images_cdn_url = nil
  end

  context "create" do
    test "staff can't create image on repo they have no admin access" do
      repo = create(:repository)
      staff = create(:staff_admin_user)

      assert_raises ActiveRecord::RecordInvalid do
        repo_image = create(:repository_image, repository: repo, uploader: staff)
      end
    end
  end

  context "audit log" do
    test "tracks creation of an image for a user repo" do
      events = subscribe("repository_image.create")

      repo = create(:repository)
      repo_image = create(:repository_image, repository: repo)

      expected_payload = {
        content_type: repo_image.content_type,
        size: repo_image.size,
        role: "open_graph",
        repo: repo.name_with_owner,
        repo_id: repo.id,
        public_repo: repo.public?,
        repository_image_id: repo_image.id,
        repository_image: repo_image.name,
        user: repo.owner.login,
        user_id: repo.owner.id,
        actor: repo_image.uploader.login,
        actor_id: repo_image.uploader_id,
      }
      assert event = events.pop, "no event was created"
      assert_equal "repository_image.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "tracks creation of an image for an org repo" do
      events = subscribe("repository_image.create")

      org = create(:organization)
      repo = create(:repository, owner: org)
      repo_image = create(:repository_image, repository: repo, uploader: org.admins.first)

      expected_payload = {
        content_type: repo_image.content_type,
        size: repo_image.size,
        role: "open_graph",
        repo: repo.name_with_owner,
        repo_id: repo.id,
        public_repo: repo.public?,
        repository_image_id: repo_image.id,
        repository_image: repo_image.name,
        org: org.login,
        org_id: org.id,
        actor: repo_image.uploader.login,
        actor_id: repo_image.uploader_id,
      }
      assert event = events.pop, "no event was created"
      assert_equal "repository_image.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "tracks deletion of an image for a user repo" do
      events = subscribe("repository_image.destroy")

      destroyer = create(:user)
      @image.destroyer = destroyer
      @image.destroy

      expected_payload = {
        content_type: @image.content_type,
        size: @image.size,
        role: "open_graph",
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        repository_image_id: @image.id,
        repository_image: @image.name,
        user: @user.login,
        user_id: @user.id,
        actor: destroyer.login,
        actor_id: destroyer.id,
      }
      assert event = events.pop, "no event was created"
      assert_equal "repository_image.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "tracks deletion of an image for an org repo" do
      events = subscribe("repository_image.destroy")

      destroyer = create(:user)
      org = create(:organization, admin: destroyer)
      repo = create(:repository, owner: org)
      repo_image = create(:repository_image, repository: repo, uploader: destroyer)
      repo_image.destroyer = destroyer
      repo_image.destroy

      expected_payload = {
        actor: destroyer.login,
        actor_id: destroyer.id,
        repo: repo.name_with_owner,
        repo_id: repo.id,
        public_repo: repo.public?,
        content_type: repo_image.content_type,
        size: repo_image.size,
        role: "open_graph",
        repository_image_id: repo_image.id,
        repository_image: repo_image.name,
        org: org.login,
        org_id: org.id,
      }
      assert event = events.pop, "no event was created"
      assert_equal "repository_image.destroy", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "Hydro events" do
    test "logs event on creation", skip_enterprise: true do
      image = RepositoryImage.new(repository: @repo, uploader: @user)

      save_file_for_uploadable image, name: "SomeCoolImage.jpg"

      message = {
        uploader: Hydro::EntitySerializer.user(@user),
        repository_image: Hydro::EntitySerializer.repository_image(image),
        repository: Hydro::EntitySerializer.repository(@repo),
      }
      assert_hydro_published(message, schema: "github.v1.RepositoryImageCreate")
    end

    test "logs event on deletion", skip_enterprise: true do
      destroyer = create(:user)
      message = {
        actor: Hydro::EntitySerializer.user(destroyer),
        destroyed_repository_image: Hydro::EntitySerializer.repository_image(@image),
      }

      @image.destroyer = destroyer
      @image.destroy

      assert_hydro_published(message, schema: "github.v1.RepositoryImageDestroy")
    end
  end

  context "#deletable_by?" do
    test "true for staff" do
      staff = create(:staff_admin_user)
      assert @image.deletable_by?(staff)
    end

    test "true for owner of the image's repository" do
      assert @image.deletable_by?(@image.repository.owner)
    end

    test "true for admin of the image's repository" do
      org_admin = create(:user)
      org = create(:organization)
      org.add_member(org_admin, action: :admin)
      org_repo = create(:repository, owner: org)
      org_repo_image = create(:repository_image, repository: org_repo, uploader: org_admin)
      assert org_repo_image.deletable_by?(org_admin)
    end

    test "false for user without admin access to the image's repository" do
      repo_member = create(:user)
      @image.repository.add_member(repo_member)
      refute @image.deletable_by?(repo_member)
    end
  end

  context "validations" do
    test "requires a unique repo and guid pair" do
      image1 = create(:repository_image)
      image2 = build(:repository_image, repository: image1.repository, guid: image1.guid)
      refute_predicate image2, :valid?
      assert_includes image2.errors[:repository_id], "has already been taken"
    end

    test "allows image content types" do
      ctypes = RepositoryImage.allowed_content_types
      assert_includes ctypes, "image/gif"
      assert_includes ctypes, "image/png"
      assert_includes ctypes, "image/jpeg"
    end

    test "requires a repository" do
      image = RepositoryImage.new(repository_id: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:repository], :present?
    end

    test "requires an uploader" do
      image = RepositoryImage.new(uploader_id: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:uploader], :present?
    end

    test "requires a content type" do
      image = RepositoryImage.new(content_type: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:content_type], :present?
    end

    test "requires a size" do
      image = RepositoryImage.new(size: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:size], :present?
    end

    if GitHub.storage_cluster_enabled?
      test "requires a storage blob" do
        image = RepositoryImage.new(storage_blob_id: nil)
        refute_predicate image, :valid?
        assert_predicate image.errors[:storage_blob], :present?
      end
    end

    test "requires uploader have admin access to repository" do
      repo = create(:repository)
      image = build(:repository_image, uploader: @user, repository: repo)
      refute_predicate image, :valid?
      assert_predicate image.errors[:uploader], :present?

      image.uploader = repo.owner
      assert_predicate image, :valid?
    end
  end

  context "initialization" do
    test "pulls content type from upload" do
      assert_equal "image/jpeg", @image.content_type
    end

    test "pulls size from upload" do
      assert_equal 1.kilobyte, @image.size
    end

    test "pulls filename from upload" do
      assert_equal "fancy-upload-of-mine.jpg", @image.name
    end

    test "sets raw asset uuid" do
      assert_equal @image, RepositoryImage.find_by(guid: @image.guid)
    end

    test "starts in the starter state" do
      assert RepositoryImage.new.starter?
    end

    test "sets state on upload" do
      assert @image.uploaded?
    end
  end

  test "deletes previous Open Graph images for the repo when a new one is created" do
    old_image = create(:repository_image)
    new_image = build(:repository_image, repository: old_image.repository)

    assert_no_difference("RepositoryImage.count") do
      assert new_image.save, "new image should have saved successfully"
    end

    refute RepositoryImage.exists?(old_image.id)
  end

  context "storage policy" do
    test "uses CDN URL if provided" do
      GitHub.repository_images_cdn_url = "https://repo-images.com/"
      assert_equal "https://repo-images.com/#{@repo.id}/#{@image.guid}", @image.storage_external_url
    end

    test "deletes S3 object without CDN" do
      assert_nil GitHub.repository_images_cdn_url

      image = create(:repository_image)
      path = "/#{image.repository_id}/#{image.guid}"
      assert_storage_policy_delete(image, path) do
        assert_enqueued_jobs(0, only: [PurgeFastlyUrlJob]) do
          image.destroy
        end
      end
    end

    test "deletes S3 object with CDN" do
      GitHub.repository_images_cdn_url = "https://repo-images.com/"

      image = create(:repository_image)
      path = "/#{image.repository_id}/#{image.guid}"
      assert_storage_policy_delete(image, path) do
        assert_purge_url image.storage_external_url do
          image.destroy
        end
      end
    end
  end
end
