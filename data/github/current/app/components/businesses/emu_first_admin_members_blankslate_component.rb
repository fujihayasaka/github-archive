# typed: strict
# frozen_string_literal: true

class Businesses::EmuFirstAdminMembersBlankslateComponent < ApplicationComponent

  sig { returns(Symbol) }
  attr_reader :page

  sig { returns(Integer) }
  attr_reader :count

  sig do
    params(
      page: Symbol,
      count: Integer
    ).void
  end
  def initialize(page:, count:)
    @page = page
    @count = count
  end

  sig { returns(T::Boolean) }
  def render?
    !!(current_user.is_first_emu_owner? && count == 1 && heading.present?)
  end

  sig { returns(String) }
  def heading
    if page == :members
      "This enterprise has no additional members"
    elsif page == :admins
      "You need additional enterprise owners"
    else
      ""
    end
  end
end
