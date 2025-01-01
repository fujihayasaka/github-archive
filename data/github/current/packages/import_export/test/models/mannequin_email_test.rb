# typed: true
# frozen_string_literal: true

require "test_helper"

class MannequinEmailTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org  = create(:organization, admin: @user)
    @mannequin = create(:mannequin, owner: @org)
  end

  context "#public?" do
    test "mannequin emails are always private" do
      refute_predicate @mannequin.emails.first, :public?
    end

    test "new mannequin emails are always private" do
      @mannequin.add_email("foo@bar.com")

      refute_predicate @mannequin.emails.last, :public?
    end
  end
end
