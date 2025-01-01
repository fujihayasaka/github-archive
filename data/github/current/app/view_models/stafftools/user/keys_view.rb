# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class KeysView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user

      def page_title
        "#{user.login} - SSH Keys"
      end

      def keys?
        keys.any?
      end

      def keys
        user.public_keys
      end
    end
  end
end
