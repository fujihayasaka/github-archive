# typed: true
# frozen_string_literal: true

module Stafftools
  class MemberView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :member

    def has_name?
      member.profile_name.present? &&
        member.profile_name.downcase != member.login.downcase
    end

  end
end
