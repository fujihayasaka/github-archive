# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationKeyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create :integration, owner: @user
  end

  context "#integration" do
    test "is required" do
      key = IntegrationKey.new creator: @user
      refute key.valid?

      assert_includes key.errors[:integration], "can't be blank"
    end

    # Attribution-only system identities are not capable of generating keys
    # because they are not permitted to access api.github.com.
    test "is invalid if the app is an attribution_only_system_identity" do
      app = create_privileged_app_with_capabilities(
        capabilities: { attribution_only_system_identity: true }
      )

      key = IntegrationKey.new integration: app, creator: app.owner
      refute key.valid?

      assert_includes key.errors[:base], "Attribution-only system identities are not permitted to create keys."
    end
  end

  context "#creator" do
    test "is required" do
      key = IntegrationKey.new integration: @integration
      refute key.valid?

      assert_includes key.errors[:creator], "can't be blank"
    end
  end

  context "#private_key" do
    test "is transient when the key is created" do
      key = IntegrationKey.create! integration: @integration, creator: @user

      assert key.private_key
      assert_kind_of OpenSSL::PKey::RSA, key.private_key

      key = IntegrationKey.find(key.id)
      assert_nil key.private_key
    end
  end

  context "#public_pem" do
    test "is derived and stored from the private key" do
      key = IntegrationKey.create! integration: @integration, creator: @user

      expected_public_pem = key.private_key.public_key.to_pem
      assert_equal expected_public_pem, key.public_pem

      key = IntegrationKey.find(key.id)
      assert_equal expected_public_pem, key.public_pem
    end
  end

  context "#public_key" do
    test "is built from the stored public_pem" do
      key = IntegrationKey.create! integration: @integration, creator: @user

      assert_equal key.public_pem, key.public_key.to_pem
    end
  end

  context "#fingerprint" do
    # https://serverfault.com/a/697634/459549
    # $ openssl rsa -in path_to_private_key -pubout -outform DER | openssl sha256 -c
    test "matches openssl fingerprint" do
      key = IntegrationKey.create! integration: @integration, creator: @user

      private_keyfile = Tempfile.new("integration.private-key.pem")
      pubkeyfile = Tempfile.new("integration.pubkey.pem", encoding: "ASCII-8BIT")
      fingerprintfile = Tempfile.new("integration.fingerprint", encoding: "ASCII-8BIT")

      begin
        private_keyfile.write(key.private_key.to_pem)
        private_keyfile.close

        # generate public key from the private key
        child = Progeny::Command.new("openssl", "rsa", "-in", private_keyfile.path, "-pubout", "-outform", "DER")
        assert_equal 0, child.status.exitstatus, "openssl rsa did not exit 0, gave #{child.status.exitstatus}: #{child.out}\n#{child.err}"

        pubkeyfile.write(child.out)
        pubkeyfile.close

        child = Progeny::Command.new("openssl", "sha256", "-binary", pubkeyfile.path)
        assert_equal 0, child.status.exitstatus, "openssl sha256 did not exit 0, gave #{child.status.exitstatus}: #{child.out}\n#{child.err}"

        fingerprintfile.write(child.out)
        fingerprintfile.close

        child = Progeny::Command.new("openssl", "base64", "-in", fingerprintfile.path)
        computed_fingerprint = child.out.chomp

        assert_equal 0, child.status.exitstatus, "openssl base64 did not exit 0, gave #{child.status.exitstatus}: #{computed_fingerprint}\n#{child.err}"
        refute_empty computed_fingerprint, "openssl base64 returned nothing"

        assert_equal "SHA256:#{computed_fingerprint}", key.fingerprint
      ensure
        fingerprintfile.close
        fingerprintfile.unlink

        pubkeyfile.close
        pubkeyfile.unlink

        private_keyfile.close
        private_keyfile.unlink
      end
    end
  end

  context "maximum keys" do
    test "prevents creating more than MAX_KEYS keys" do
      IntegrationKey.create! integration: @integration, creator: @user

      key = T.let(nil, T.nilable(IntegrationKey))
      IntegrationKey.stub_const(:MAX_KEYS, 1) do
        key = IntegrationKey.new integration: @integration, creator: @user

        refute key.valid?
        assert_includes T.must(key).errors[:base], "You cannot have more than #{IntegrationKey::MAX_KEYS} private keys."
      end
    end
  end

  context "#destroy" do
    test "prevents deleting the only key" do
      key = IntegrationKey.create! integration: @integration, creator: @user

      key.destroy

      refute_empty key.errors
      assert_equal key, IntegrationKey.find_by(id: key.id)
    end

    test "deletes key when at least one would remain" do
      key = IntegrationKey.create! integration: @integration, creator: @user
      _other_key = IntegrationKey.create! integration: @integration, creator: @user

      key.destroy

      assert_empty key.errors
      assert_nil IntegrationKey.find_by(id: key.id)
    end

    test "allows deleting the only key when deleting the owning integration" do
      key = IntegrationKey.create! integration: @integration, creator: @user

      @integration.destroy

      assert_empty @integration.errors
      assert_empty key.errors
      assert_nil IntegrationKey.find_by(id: key.id)
    end
  end
end
