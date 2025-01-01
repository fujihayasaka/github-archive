# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
  end

  context ".for" do
    test "returns user accesses for a user owner" do
      pats = 3.times.map { create(:user_programmatic_access, owner: @user) }
      result = ProgrammaticAccess.for(@user)
      assert_same_elements result, pats
    end

    test "does not return accesses for users who are not the owner" do
      pat = create(:user_programmatic_access)
      result = ProgrammaticAccess.for(@user)
      refute_equal pat.owner, @user
      assert_empty result
    end
  end

  context ".granted_on" do
    test "returns accesses granted on an given org" do
      org = create(:organization)
      pats = 3.times.map do
        member = create(:user)
        org.add_member(member)
        make_user_programmatic_access_with_grant(requester: member, target: org)
      end

      result = ProgrammaticAccess.granted_on(org)
      assert_same_elements result, pats
    end

    test "returns accesses granted on an given user" do
      pats = 3.times.map { make_user_programmatic_access_with_grant(requester: @user, target: @user) }
      result = ProgrammaticAccess.granted_on(@user)

      assert_same_elements result, pats
    end
  end

  context ".new_access" do
    test "returns a new instance of an access for a user owner" do
      pat = ProgrammaticAccess.new_access(@user)
      assert_instance_of UserProgrammaticAccess, pat
      assert_equal pat.owner, @user
    end

    test "it does not persist the access in the database" do
      assert_equal UserProgrammaticAccess.count, 0
      ProgrammaticAccess.new_access(@user)
      assert_equal UserProgrammaticAccess.count, 0
    end

    test "it assigns any of the attributes passed" do
      attrs = {
        name: "Auntie Grizelda",
        description: "she knows her mind all right"
      }
      pat = ProgrammaticAccess.new_access(@user, attrs)
      pat.save
      assert_equal pat.name, attrs[:name]
      assert_equal pat.description, attrs[:description]
    end
  end

  context ".destroy" do
    test "calls ProgrammaticAccess::Destroyer" do
      pat = create(:user_programmatic_access)
      ::ProgrammaticAccess::Destroyer.expects(:perform).with(pat, :web_user)
      ProgrammaticAccess.destroy(pat, :web_user)
    end
  end

  context ".owner_can_be_notified?" do
    test "is false for event types not included in NOTIFIABLE_EVENTS" do
      pat = create(:user_programmatic_access)
      refute ProgrammaticAccess.owner_can_be_notified?(pat, event_type: :minted)
    end

    test "is true for known events triggered out of threshold" do
      pat = create(:user_programmatic_access)

      Timecop.freeze(Time.now) do
        assert ProgrammaticAccess.owner_can_be_notified?(pat, event_type: :created)
      end

      Timecop.freeze(Time.now + 2.hours) do
        assert ProgrammaticAccess.owner_can_be_notified?(pat, event_type: :created)
      end
    end

    test "is false for known events triggered within threshold" do
      pat = create(:user_programmatic_access)

      Timecop.freeze(Time.now) do
        assert ProgrammaticAccess.owner_can_be_notified?(pat, event_type: :created)
      end

      Timecop.freeze(Time.now + 10.minutes) do
        refute ProgrammaticAccess.owner_can_be_notified?(pat, event_type: :created)
      end
    end
  end

  context ".find" do
    test "returns the access if it exists" do
      access = create(:user_programmatic_access)
      assert_equal access, ProgrammaticAccess.find(access.id)
    end

    test "raises an error if the access does not exist" do
      assert_raises ActiveRecord::RecordNotFound do
        ProgrammaticAccess.find(0)
      end
    end
  end

  context ".find_or_nil" do
    test "returns the access if it exists" do
      access = create(:user_programmatic_access)
      assert_equal access, ProgrammaticAccess.find_or_nil(access.id)
    end

    test "returns nil if the access does not exist" do
      assert_nil ProgrammaticAccess.find_or_nil(0)
    end
  end
end
