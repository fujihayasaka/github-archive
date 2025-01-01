# typed: true
# frozen_string_literal: true

require "test_helper"

class SshKeyFormTest < GitHub::TestCase

  setup do
    fixture_dir = Rails.root.join("test", "fixtures", "keys")
    @test_keys = {
      valid: File.read("#{fixture_dir}/valid.pub"),
    }
  end

  fixtures do
    @mojombo = create(:user, login: "mojombo")
  end

  context "create_key" do
    test "returns the form object itself if the key_type is invalid" do
      form = SshKeyForm.new(title: "foo", key: "ignored", current_user: @mojombo, key_type: "invalid")
      assert_equal form.create_key, form
      assert form.errors[:key_type].present?
    end

    test "persists a new verified user public key when the key_type is 'authentication" do
      form = SshKeyForm.new(title: "foo", key: @test_keys[:valid], current_user: @mojombo, key_type: "authentication")
      assert form.valid?
      key = form.create_key
      assert key.is_a?(PublicKey)
      assert key.persisted?
      assert_equal key.user, @mojombo
      assert_equal key.title, "foo"
      refute key.read_only?
      assert key.verified?
    end

    test "returns an invalid public key with its errors" do
      form = SshKeyForm.new(title: "foo", key: nil, current_user: @mojombo, key_type: "authentication")
      assert form.valid?
      key = form.create_key
      assert key.is_a?(PublicKey)
      refute key.persisted?
      assert key.errors[:key].present?
    end

    test "persists a new git_signing_ssh_public_key when the key_type is 'signing'" do
      form = SshKeyForm.new(title: "foo", key: @test_keys[:valid], current_user: @mojombo, key_type: "signing")
      assert form.valid?
      key = form.create_key
      assert key.is_a?(GitSigningSshPublicKey)
      assert key.persisted?
      assert_equal key.user, @mojombo
      assert_equal key.title, "foo"
    end

    test "returns an invalid signing key with errors" do
      form = SshKeyForm.new(title: "foo", key: nil, current_user: @mojombo, key_type: "signing")
      assert form.valid?
      key = form.create_key
      assert key.is_a?(GitSigningSshPublicKey)
      refute key.persisted?
      assert key.errors[:key].present?
    end
  end

  context "new_record?" do
    test "returns true if the form object itself is invalid" do
      form = SshKeyForm.new(title: "foo", key: nil, current_user: @mojombo, key_type: "")
      refute form.valid?
      assert form.new_record?
    end

    test "returns false if the form object is valid" do
      form = SshKeyForm.new(title: "foo", key: nil, current_user: @mojombo, key_type: "signing")
      assert form.valid?
      refute form.new_record?
    end
  end
end
