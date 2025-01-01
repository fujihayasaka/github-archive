# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgMembershipUpdaterTest < GitHub::TestCase

  fixtures do
    3.times do
      user = create :user
      org = create :organization
      org.add_member user
    end
  end

  if GitHub.enterprise?
    test "raises ArgumentError when membership_visibility is invalid" do
      assert_raises ArgumentError, /membership_visibility must be "public" or "private"/ do
        OrgMembershipUpdater.new(membership_visibility: "whatevs").run
      end
    end

    test "bulk-updates all org memberships to public" do
      conceal_all
      OrgMembershipUpdater.new(membership_visibility: "public").run

      Organization.find_each do |org|
        org.people.each do |member|
          assert org.public_member?(member)
        end
      end
    end

    test "bulk-updates all org memberships to private" do
      publicize_all
      OrgMembershipUpdater.new(membership_visibility: "private").run

      Organization.find_each do |org|
        org.people.each do |member|
          refute org.public_member?(member)
        end
      end
    end
  else
    test "doesn't run outside Enterprise" do
      assert_raises OrgMembershipUpdater::Error, /Updating organization memberships in bulk is only supported on GitHub Enterprise/ do
        OrgMembershipUpdater.new(membership_visibility: "public").run
      end
    end
  end

  def conceal_all
    Organization.find_each do |org|
      org.public_members.each do |member|
        org.conceal_member(member)
      end
    end
  end

  def publicize_all
    Organization.find_each do |org|
      org.people.each do |member|
        org.publicize_member(member)
      end
    end
  end
end
