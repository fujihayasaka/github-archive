# typed: false
# frozen_string_literal: true

module Events
  class MemberView < View
    def title_text
      parts = [actor_text, actor_bot_identifier_text, action, member_text, "to", repo_text]
      parts.compact.join(" ")
    end

    def member_login
      case payload[:member]
      when Hash
        payload[:member][:login]
      else
        member.try(:login) || ""
      end
    end

    def icon
      action =~ /add/i ? "member_add" : "member_remove"
    end

    private

    def member_text
      member_login || "someone"
    end

    # do not call this
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def member
      @member ||= unless defined?(@member)
        case id = payload[:member]
        when Integer
          User.find_by_id(id)
        when String
          User.find_by_login(id)
        else
          nil
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  end
end
