# typed: true
# frozen_string_literal: true

require "test_helper"

class LicenseSourcerTest < GitHub::TestCase
  context ".empty" do
    test "returns an empty list of sources" do
      assert_equal [], LicenseSourcer.empty.values
    end
  end

  context ".members" do
    test "returns values with member source" do
      org = create(:organization)

      sources = LicenseSourcer.members(org, [1])
      origin = sources[1].first
      assert_equal :member, origin.association
      assert_equal org, origin.owner
    end
  end

  context ".collaborators" do
    test "returns values with collaborator source" do
      org = create(:organization)
      sources = LicenseSourcer.collaborators(org, [1])
      origin = sources[1].first
      assert_equal :collaborator, origin.association
      assert_equal org, origin.owner
    end
  end

  context ".collaborator_invites" do
    test "returns values with collaborator invite source" do
      org = create(:organization)
      sources = LicenseSourcer.collaborator_invites(org, [1])
      origin = sources[1].first
      assert_equal :collaborator_invite, origin.association
      assert_equal org, origin.owner
    end
  end

  context ".invites" do
    test "returns values with invite source" do
      org = create(:organization)
      sources = LicenseSourcer.invites(org, [1])
      origin = sources[1].first
      assert_equal :invite, origin.association
      assert_equal org, origin.owner
    end
  end

  context "#+" do
    test "returns a new license source with both values" do
      org = create(:organization)
      first_source = LicenseSourcer.invites(org, [1])
      second_source = LicenseSourcer.invites(org, [2])

      combined_source = first_source + second_source

      assert_equal [1], first_source.values, "first source mutated"
      assert_equal [2], second_source.values, "second source mutated"
      assert_equal [1, 2], combined_source.values
    end

    test "combines duplicate keys to contain both sources" do
      org = create(:organization)
      first_source = LicenseSourcer.invites(org, [1])
      other_org = create(:organization)
      second_source = LicenseSourcer.members(other_org, [1])

      combined_source = first_source + second_source
      first_origin = combined_source[1].first
      second_origin = combined_source[1].last

      assert_equal :invite, first_origin.association
      assert_equal org, first_origin.owner
      assert_equal :member, second_origin.association
      assert_equal other_org, second_origin.owner
    end
  end

  context "#-" do
    test "removes values from first array that are also in second array" do
      org = create(:organization)
      first_source = LicenseSourcer.invites(org, [1, 2])
      other_org = create(:organization)
      second_source = LicenseSourcer.members(other_org, [1, 3])

      subtracted_source = first_source - second_source

      assert_equal [2], subtracted_source.values
    end
  end

  context LicenseSourcer::LicenseOrigin do
    context "#to_s" do
      test "when member" do
        org = build(:organization, login: "github")
        origin = LicenseSourcer::LicenseOrigin.new(org, :member)

        assert_equal "member of github", origin.to_s
      end

      test "when admin" do
        org = build(:organization, login: "github")
        origin = LicenseSourcer::LicenseOrigin.new(org, :admin)

        assert_equal "admin of github", origin.to_s
      end

      test "when invite" do
        org = build(:organization, login: "github")
        origin = LicenseSourcer::LicenseOrigin.new(org, :invite)

        assert_equal "invited to github", origin.to_s
      end

      test "when collaborator" do
        org = build(:organization, login: "github")
        origin = LicenseSourcer::LicenseOrigin.new(org, :collaborator)

        assert_equal "private repo collaborator on github", origin.to_s
      end

      test "when invited collaborator" do
        org = build(:organization, login: "github")
        origin = LicenseSourcer::LicenseOrigin.new(org, :collaborator_invite)

        assert_equal "invited private repo collaborator on github", origin.to_s
      end
    end
  end
end
