# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # UserFilter matches <gh:user-reference> elements. It performs authorization checks for user references.
  #
  # To use this authorization check in non-authorization HTML Pipeline filters, include GitHub::Goomba::Reference::Helpers
  # into a filter and call user_reference_wrapper, e.g.
  #
  # class MyFilter < NodeFilter
  #   include GitHub::Goomba::Reference::Helpers
  #   def call(node)
  #     login = node.inner_html.gsub("@", "")
  #
  #     # return an authorization wrapper that the Authorization::UserFilter will use to perform an
  #     # authorization check on a user mention, including the content that authorized and unauthorized viewers should see
  # user_reference_wrapper(login) do |wrapper|
  #       wrapper.authorized { "Hi! @#{login}" }
  #       wrapper.unauthorized { "I can't mention @#{login} :sad:" }
  #     end
  #   end
  # end
  class UserFilter < ReferenceFilter
    ELEMENT = "gh:user-reference".freeze
    SELECTOR = Goomba::Selector.new(match: ELEMENT.gsub(":", "|"))

    def selector
      SELECTOR
    end

    def async_check_authorization(nodes)
      check_emu_access(nodes)
      Promise.resolve
    end

    private

    # Check whether a viewer should see rich user mentions based on EMU visibility rules
    def check_emu_access(nodes)
      return if nodes.empty?

      current_tenant = GitHub::CurrentTenant.get

      is_emu = current_user&.is_enterprise_managed?
      _, shortcode = current_user.try(:login).to_s.split("_", 2)

      # group the uuids by login, so we only need to evaluate each login once
      nodes_by_login = Hash.new { |hsh, k| hsh[k] = [] }
      nodes.each do |node|
        nodes_by_login[node["login"]] << node
      end

      nodes_by_login.each do |login, nodes|
        next if login.blank?

        if current_tenant
          # Users in a multi-tenant environment must be referenced without a suffix,
          # which will resolve to matching users in the current tenant.
          next if login.include?("_")
        elsif !current_user&.bot?
          # enterprise managed users can't reference non-enterprise managed users
          # or users from a different enterprise
          next if is_emu && !login.include?("_#{shortcode}")

          # non-enterprise managed users can't reference enterprise managed users
          next if !is_emu && login.include?("_")
        else
          if login.include?("_")
            # bot trying to mention an EMU user
            if business = repository&.owner&.business
              # if the mention happens in a repo owned by a business, check the mentioned user is in the same business
              next unless login.include?("_#{business.shortcode}")
            end
          end
        end

        authorized_nodes.merge(nodes)
      end
    end

    # When the viewer doesn't have access to see a user, remove any references to the mentioned user
    # from the result object
    def access_denied(node)
      login = node["login"].downcase
      result[:mentioned_users].try(:delete_if) { |u| u.login.downcase == login }
      result[:mentioned_usernames].try(:delete_if) { |name| name.downcase == login }
    end
  end
end
