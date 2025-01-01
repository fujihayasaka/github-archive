# typed: false
# frozen_string_literal: true

require "test_helper"

class LoggedPushTest < GitHub::TestCase
  fixtures do
    # The example repo has borrowed an audit_log from
    # a real repo where the user and/or deploy key
    # verifier ID is 6218. We need to ensure that
    # matching users/pushers exist to be found and associated
    # with LoggedPush entries.
    @user  = User.find_by_id(6218) || create(:user, id: 6218)
    @hubot = User.find_by_login("hubot") || create(:user, login: "hubot")
    @repo  = create(:repository, owner: @user, from_example: :pushlog_with_deploy_keys)


    @org_ca = create(:ssh_certificate_authority, :org)
    @business_ca = create(:ssh_certificate_authority, :business)
  end

  setup do
    reflog = @repo.reflog("refs/heads/master")
    @user_push       = reflog.detect { |ent| !ent.user_id.nil? && ent.pubkey_verifier_id.nil? }
    @deploy_key_push = reflog.detect { |ent|  ent.user_id.nil? && !ent.pubkey_verifier_id.nil? }
    @mirror_push     = reflog.detect { |ent|  ent.name == "mirror" }
  end

  test "pusher names have the right encoding" do
    assert_equal Encoding::UTF_8, @user_push.name.encoding
    assert @user_push.name.valid_encoding?
  end

  test "push from a user" do
    assert_equal @user, @user_push.user
    assert_nil @user_push.deploy_key_verifier
  end

  test "push from a user has no deploy key" do
    refute @user_push.deploy_key?
  end

  test "push from a deploy key" do
    assert_equal @user, @deploy_key_push.deploy_key_verifier
    assert_nil @deploy_key_push.user
  end

  test "push from a deploy key has a deploy key" do
    assert @deploy_key_push.deploy_key?
  end

  # Eg. "push" from Mirror.perform! spawning git-fetch
  test "push with a pusher instead of a user/pubkey" do
    assert_equal @hubot, @mirror_push.user
  end

  context "when pushing one ref" do
    test "has one target" do
      assert_equal 1, @user_push.targets.size
    end
  end

  context "#ssh_cert_description" do
    test "without ssh cert" do
      push = LoggedPush.new

      refute_predicate push, :ssh_cert?
      assert_nil push.ssh_ca_owner_description
      assert_nil push.ssh_ca_description
      assert_nil push.ssh_cert_description
    end

    test "with business ca" do
      push = LoggedPush.from(
        ssh_ca_id: @business_ca.id,
        ssh_ca_owner_type: @business_ca.owner_type,
        ssh_ca_owner_id: @business_ca.owner_id,
      )

      assert_predicate push, :ssh_cert?
      assert_equal "type=enterprise id=#{@business_ca.owner_id} slug=#{@business_ca.owner.slug}", push.ssh_ca_owner_description
      assert_equal "id=#{@business_ca.id} fpr=#{@business_ca.base64_fingerprint}", push.ssh_ca_description
      assert_equal "a SSH certificate", push.ssh_cert_description
    end

    test "with org ca" do
      push = LoggedPush.from(
        ssh_ca_id: @org_ca.id,
        ssh_ca_owner_type: @org_ca.owner_type,
        ssh_ca_owner_id: @org_ca.owner_id,
      )

      assert_predicate push, :ssh_cert?
      assert_equal "type=organization id=#{@org_ca.owner_id} login=#{@org_ca.owner.login}", push.ssh_ca_owner_description
      assert_equal "id=#{@org_ca.id} fpr=#{@org_ca.base64_fingerprint}", push.ssh_ca_description
      assert_equal "a SSH certificate", push.ssh_cert_description
    end

    test "with deleted business ca" do
      push = LoggedPush.from(
        ssh_ca_id: 1234,
        ssh_ca_owner_type: @business_ca.owner_type,
        ssh_ca_owner_id: @business_ca.owner_id,
      )

      assert_predicate push, :ssh_cert?
      assert_equal "type=enterprise id=#{@business_ca.owner_id} slug=#{@business_ca.owner.slug}", push.ssh_ca_owner_description
      assert_equal "id=1234", push.ssh_ca_description
      assert_equal "a SSH certificate", push.ssh_cert_description
    end

    test "with deleted org ca" do
      push = LoggedPush.from(
        ssh_ca_id: 1234,
        ssh_ca_owner_type: @org_ca.owner_type,
        ssh_ca_owner_id: @org_ca.owner_id,
      )

      assert_predicate push, :ssh_cert?
      assert_equal "type=organization id=#{@org_ca.owner_id} login=#{@org_ca.owner.login}", push.ssh_ca_owner_description
      assert_equal "id=1234", push.ssh_ca_description
      assert_equal "a SSH certificate", push.ssh_cert_description
    end

    test "with deleted business" do
      push = LoggedPush.from(
        ssh_ca_id: 1234,
        ssh_ca_owner_type: ::Business.name,
        ssh_ca_owner_id: 2345,
      )

      assert_predicate push, :ssh_cert?
      assert_equal "type=enterprise id=2345", push.ssh_ca_owner_description
      assert_equal "id=1234", push.ssh_ca_description
      assert_equal "a SSH certificate", push.ssh_cert_description
    end

    test "with deleted org" do
      push = LoggedPush.from(
        ssh_ca_id: 1234,
        ssh_ca_owner_type: ::Organization.base_class.name,
        ssh_ca_owner_id: 2345,
      )

      assert_predicate push, :ssh_cert?
      assert_equal "type=organization id=2345", push.ssh_ca_owner_description
      assert_equal "id=1234", push.ssh_ca_description
      assert_equal "a SSH certificate", push.ssh_cert_description
    end
  end
end
