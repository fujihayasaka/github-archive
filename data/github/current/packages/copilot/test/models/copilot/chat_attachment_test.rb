# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::ChatAttachmentTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include CopilotPublicUserCacheable
  include UploadableTestHelpers
  include HydroTestHelpers

  skip_enterprise

  fixtures do
    @user = create(:user)
    @uploaded_attachment = save_file_for_uploadable(Copilot::ChatAttachment.new(uploader: @user))
  end

  context "#storage_s3_access_key" do
    test "returns Azure storage account" do
      GitHub.stubs(:copilot_chat_attachment_azure_storage_account).returns("foo")
      assert_equal "foo", @uploaded_attachment.storage_s3_access_key
    end
  end

  context "#storage_s3_secret_key" do
    test "returns Azure storage access key" do
      GitHub.stubs(:copilot_chat_attachment_azure_storage_access_key).returns("bar")
      assert_equal "bar", @uploaded_attachment.storage_s3_secret_key
    end
  end

  context "initialization" do
    test "pulls content type from upload" do
      assert_equal "image/jpeg", @uploaded_attachment.content_type
    end

    test "pulls size from upload" do
      assert_equal 1.kilobyte, @uploaded_attachment.size
    end

    test "pulls filename from upload" do
      assert_equal "pug.jpeg", @uploaded_attachment.name
    end

    test "sets raw asset uuid" do
      assert_equal @uploaded_attachment, Copilot::ChatAttachment.find_by(guid: @uploaded_attachment.guid)
    end

    test "starts in the starter state" do
      assert_predicate Copilot::ChatAttachment.new, :starter?
    end

    test "sets state on upload" do
      assert_predicate @uploaded_attachment, :uploaded?
    end
  end

  context ".allowed_content_types" do
    test "allows image content types" do
      content_types = Copilot::ChatAttachment.allowed_content_types
      assert_includes content_types, "image/gif"
      assert_includes content_types, "image/png"
      assert_includes content_types, "image/jpeg"
      refute_includes content_types, "video/quicktime"
      refute_includes content_types, "video/mp4"
    end
  end

  context "validation" do
    test "requires an uploader" do
      models_attachment = Copilot::ChatAttachment.new(uploader_id: nil)
      refute_predicate models_attachment, :valid?
      assert_includes models_attachment.errors[:uploader], "can't be blank"
    end

    test "requires a content type" do
      models_attachment = Copilot::ChatAttachment.new(content_type: nil)
      refute_predicate models_attachment, :valid?
      assert_includes models_attachment.errors[:content_type], "is not included in the list"
    end

    test "requires size to be within limit" do
      too_big_size = (Copilot::ChatAttachment::SIZE_LIMIT_IN_MEGABYTES + 1).megabytes
      models_attachment = Copilot::ChatAttachment.new(size: too_big_size)
      refute_predicate models_attachment, :valid?
      error_message = models_attachment.errors[:size].first
      refute_nil error_message
      assert_includes error_message, "File is too big"
    end

    test "sanitizes file name" do
      assert_name_sanitization Copilot::ChatAttachment
    end

    test "requires file extension to match content type" do
      models_attachment = Copilot::ChatAttachment.new(uploader: @user)
      err = assert_raises(ActiveRecord::RecordInvalid) do
        save_file_for_uploadable models_attachment, name: "pug.html", content_type: "image/jpeg"
      end
      assert_includes err.record.errors[:name], "has a file extension that does not match the content type"
    end
  end

  context "uploaded_by scope" do
    test "filters by uploader" do
      other_user = create(:user)
      base_scope = Copilot::ChatAttachment.where(id: [@uploaded_attachment.id])

      assert_equal [@uploaded_attachment], base_scope.uploaded_by(@user)
      assert_empty base_scope.uploaded_by(other_user)
    end
  end

  context "#target_for_conditional_access and #async_target_for_conditional_access" do
    test "returns the user who uploaded the attachment" do
      expected = @uploaded_attachment.uploader
      refute_nil expected

      assert_equal expected, @uploaded_attachment.target_for_conditional_access
      assert_equal expected, @uploaded_attachment.async_target_for_conditional_access.sync
    end
  end

  context "hydro instrumentation" do
    test "emits a hydro event when the attachment is uploaded by a copilot free user" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        subscribed: true,
        free_user_type: Copilot::FreeUser::COMPLIMENTARY_ACCESS.name,
        last_checked_date: Date.new(9999, 12, 31),
      )

      reset_hydro

      ip_address = "1.2.3.4"
      GitHub.context.push(actor_ip: ip_address)
      attachment = Copilot::ChatAttachment.new(uploader: user)
      save_file_for_uploadable(attachment)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        upload_ip: Hydro::EntitySerializer.ip_address(ip_address),
        image_model: Hydro::EntitySerializer.image_attachment(attachment),
      }

      assert_hydro_published(message, schema: "github.trust_safety.v0.ImageScan")
      assert_hydro_messages(count: 1, schema: "github.trust_safety.v0.ImageScan")
    end

    test "emits a hydro event when the attachment is uploaded by a copilot limited user" do
      copilot_user = create(:copilot_limited_user)
      user = copilot_user.user

      reset_hydro

      ip_address = "1.2.3.4"
      GitHub.context.push(actor_ip: ip_address)
      attachment = Copilot::ChatAttachment.new(uploader: user)
      save_file_for_uploadable(attachment)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        upload_ip: Hydro::EntitySerializer.ip_address(ip_address),
        image_model: Hydro::EntitySerializer.image_attachment(attachment),
      }

      assert_hydro_published(message, schema: "github.trust_safety.v0.ImageScan")
      assert_hydro_messages(count: 1, schema: "github.trust_safety.v0.ImageScan")
    end

    test "does not emit a hydro scan event for Copilot Enterprise users" do
      copilot_enterprise_seat = create(:copilot_seat, copilot_plan: "enterprise")
      user = copilot_enterprise_seat.assigned_user

      reset_hydro

      ip_address = "1.2.3.4"
      GitHub.context.push(actor_ip: ip_address)
      attachment = Copilot::ChatAttachment.new(uploader: user)

      save_file_for_uploadable(attachment)

      refute_hydro_messages(schema: "github.trust_safety.v0.ImageScan")
    end

    test "does not emit a hydro scan event for Copilot Business users" do
      copilot_business_seat = create(:copilot_seat)
      user = copilot_business_seat.assigned_user

      reset_hydro

      ip_address = "1.2.3.4"
      GitHub.context.push(actor_ip: ip_address)
      attachment = Copilot::ChatAttachment.new(uploader: user)

      save_file_for_uploadable(attachment)

      refute_hydro_messages(schema: "github.trust_safety.v0.ImageScan")
    end
  end
end
