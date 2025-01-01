# typed: true
# frozen_string_literal: true

require "test_helper"

class SamlMappingModelTest < GitHub::TestCase
  fixtures do
    create(:user)
    @map = create :user_saml_mapping
    @migratable_user = create :migratable_user_saml_mapping
  end

  test "mapping has a user, name id and name id format" do
    assert @map.user
    assert_equal @map.name_id, @map.user.login
    assert_equal @map.name_id_format, "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
    assert @map.valid?
  end

  test "mapping fails if the user already has a mapping" do
    new_user = create(:user)

    assert_raises ActiveRecord::RecordInvalid do
      new_map = create :user_saml_mapping, user: new_user, name_id: @map.user.login, name_id_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
    end
  end

  test "mapping fails if the login is taken and the name id format is different" do
    new_user = create(:user)

    assert_raises ActiveRecord::RecordInvalid do
      new_map = create :user_saml_mapping, user: new_user, name_id: @map.user.login, name_id_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:email-address"
    end
  end

  test "#migrate_mapping! will update the name_id if the name id and login match and the name id from the saml response is different" do
    assert @migratable_user.user
    assert_equal @migratable_user.name_id, @migratable_user.user.login
    assert_equal @migratable_user.name_id_format, "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
    assert_predicate @migratable_user, :valid?
    assert @migratable_user.need_migration?("2", @migratable_user.user.login)
    @migratable_user.migrate_mapping!("2", @migratable_user.user.login)

    @migratable_user.reload
    refute_equal @migratable_user.name_id, @migratable_user.user.login
    assert_equal @migratable_user.name_id, "2"
  end

  test "#migrate_mapping! will not update the name_id if the login match the saml response name id" do
    assert @migratable_user.user
    assert_equal @migratable_user.name_id, @migratable_user.user.login
    assert_equal @migratable_user.name_id_format, "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
    assert_predicate @migratable_user, :valid?
    refute @migratable_user.need_migration?(@migratable_user.user.login, @migratable_user.user.login)
  end
end
