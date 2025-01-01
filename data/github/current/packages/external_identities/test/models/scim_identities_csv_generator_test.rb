# typed: true
# frozen_string_literal: true

require "test_helper"

class ScimIdentitiesCSVGeneratorTest < GitHub::TestCase
  include AuthenticationHelpers::SAML

  skip_unless :enterprise?

  fixtures do
    @enterprise = create(:global_business)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  context "#new" do
    test "raises an error when SCIM is disabled" do
      setup_saml_auth_mode(with_scim: false)

      expected_message = "SCIM identities csv generation does not work when SCIM is disabled. SCIM identities are destroyed once SCIM is disabled."

      assert_raises_with_message(ScimIdentitiesCSVGenerator::Error, expected_message) do
        ScimIdentitiesCSVGenerator.new(output_io: StringIO.new)
      end
    end

    test "does not raise an error when SCIM is enabled" do
      assert_nothing_raised do
        ScimIdentitiesCSVGenerator.new(output_io: StringIO.new)
      end
    end
  end

  context "#run" do
    test "returns SCIM identity info without headers and 1 group membership" do
      user_1_group = create(:ghes_scim_user, business: @enterprise, login: "saml-scim-1-group")
      external_identity = user_1_group.external_identities.first
      group = create :external_group, :with_members, users: [user_1_group], business: @enterprise

      io = StringIO.new
      generator = ScimIdentitiesCSVGenerator.new output_io: io, header: false

      generator.run
      io.rewind
      csv = CSV.parse T.must(io.read)
      row = T.must(csv.first)

      assert_equal external_identity.id.to_s, row[0]
      assert_equal user_1_group.id.to_s, row[1]
      assert_equal user_1_group.login, row[2]
      assert_equal external_identity.user_name, row[3]
      assert_equal external_identity.external_id, row[4]
      assert_equal external_identity.guid, row[5]
      assert_equal group.display_name, row[6]
    end

    test "returns mappings with headers" do
      user_1_group = create(:ghes_scim_user, business: @enterprise, login: "saml-scim-1-group")
      external_identity = user_1_group.external_identities.first
      group = create :external_group, :with_members, users: [user_1_group], business: @enterprise

      io = StringIO.new
      generator = ScimIdentitiesCSVGenerator.new output_io: io, header: true

      generator.run
      io.rewind
      csv = CSV.parse T.must(io.read)
      header = T.must(csv[0])
      row = T.must(csv[1])

      assert_equal "external_identity_id", header[0]
      assert_equal "user_id", header[1]
      assert_equal "login", header[2]
      assert_equal "user_name", header[3]
      assert_equal "external_id", header[4]
      assert_equal "scim_user_id", header[5]
      assert_equal "groups", header[6]

      assert_equal external_identity.id.to_s, row[0]
      assert_equal user_1_group.id.to_s, row[1]
      assert_equal user_1_group.login, row[2]
      assert_equal external_identity.user_name, row[3]
      assert_equal external_identity.external_id, row[4]
      assert_equal external_identity.guid, row[5]
      assert_equal group.display_name, row[6]
    end

    test "returns nil groups if no group memberships exist" do
      user_no_groups = create(:ghes_scim_user, business: @enterprise, login: "saml-scim-no-groups")
      external_identity = user_no_groups.external_identities.first

      io = StringIO.new
      generator = ScimIdentitiesCSVGenerator.new output_io: io, header: false

      generator.run
      io.rewind
      csv = CSV.parse T.must(io.read)
      row = T.must(csv.first)

      assert_equal external_identity.id.to_s, row[0]
      assert_equal user_no_groups.id.to_s, row[1]
      assert_equal user_no_groups.login, row[2]
      assert_equal external_identity.user_name, row[3]
      assert_equal external_identity.external_id, row[4]
      assert_equal external_identity.guid, row[5]
      assert_nil row[6]
    end

    test "returns multiple group memberships" do
      user_2_groups = create(:ghes_scim_user, business: @enterprise, login: "saml-scim-2-groups")
      external_identity = user_2_groups.external_identities.first
      group1 = create :external_group, :with_members, users: [user_2_groups], business: @enterprise
      group2 = create :external_group, :with_members, users: [user_2_groups], business: @enterprise

      io = StringIO.new
      generator = ScimIdentitiesCSVGenerator.new output_io: io, header: false

      generator.run
      io.rewind
      csv = CSV.parse T.must(io.read)
      row = T.must(csv.first)

      assert_equal external_identity.id.to_s, row[0]
      assert_equal user_2_groups.id.to_s, row[1]
      assert_equal user_2_groups.login, row[2]
      assert_equal external_identity.user_name, row[3]
      assert_equal external_identity.external_id, row[4]
      assert_equal external_identity.guid, row[5]
      assert_includes row[6], group1.display_name
      assert_includes row[6], group2.display_name
    end
  end
end
