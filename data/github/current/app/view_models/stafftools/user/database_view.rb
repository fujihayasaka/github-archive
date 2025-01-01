# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class DatabaseView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user

      def page_title
        "#{user} - Database"
      end

      def columns
        if GitHub.enterprise?
          %w(id login created_at updated_at last_ip)
        else
          cols = %w(id global_relay_id next_global_id login created_at updated_at last_ip)
          cols += ::User.attribute_names.sort
          cols -= %w(raw_data auth_token bcrypt_auth_token token_secret password_hash)
          cols.uniq
        end
      end

      def value(column)
        v = user.send(column)
        v = "nil" if v.to_s.blank?
        v.to_s.dup.force_encoding("UTF-8").valid_encoding? ? v : "cannot be displayed"
      end
    end
  end
end
