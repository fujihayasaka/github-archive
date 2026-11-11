# typed: true
# frozen_string_literal: true

module Stafftools
  class MemberView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :member

    def has_name?
      member.display_name.present? &&
        member.display_name.downcase != member.login.downcase
    end
  end
end
