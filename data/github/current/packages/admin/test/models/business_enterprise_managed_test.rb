# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessEnterpriseManagedTest < GitHub::TestCase
  context "factory" do
    context ":enterprise_managed trait" do
      test "is enterprise managed" do
        assert_predicate create(:business, :enterprise_managed), :enterprise_managed?
      end

      test "have first enterprise owner as an admin by default" do
        emu_biz = create(:business, :enterprise_managed)
        assert_equal 1, emu_biz.owners.size
        assert emu_biz.find_first_emu_owner.instance_of?(User)
      end
    end

    context ":without_enterprise_managed_user_owner trait" do
      test "no-op when passed in without :enterprise_managed trait" do
        biz = create(:business, :without_enterprise_managed_user_owner)
        assert_equal 1, biz.owners.size
        assert_nil biz.find_first_emu_owner
      end

      test "have no owner in the emu enabled enterprise" do
        emu_biz = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)

        # assert if business is emu
        assert_predicate create(:business, :enterprise_managed), :enterprise_managed?

        # assert no owners
        assert_empty emu_biz.owners
        assert_nil emu_biz.find_first_emu_owner
      end
    end
  end
end unless GitHub.enterprise?
