# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Owner < Base

        sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs
        sig { returns(Business) }; attr_reader :business
        sig { returns(User) }; attr_reader :user

        sig { params(authorized_orgs: T::Array[Organization], business: Business, user: User, kwargs: T.untyped).void }
        def initialize(authorized_orgs:, business:, user:, **kwargs)
          super(**T.unsafe(kwargs))
          @authorized_orgs = authorized_orgs
          @business = business
          @user = user
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          # Short-circuit if the user is not authorized to view any orgs
          # **and** the business does not support emu repos.
          return [] if authorized_orgs.blank? && !include_emus?

          suggestions = []

          if authorized_orgs.any?
            orgs = without_selected_values
              .select { |o| o.display_login.include?(value) }
              .sort_by(&:display_login)
              .take(limit)

            org_suggestions = orgs.map do |org|
              ::SecurityCenter::Suggestions::Suggestion.new(value: org.display_login, description: "Organization")
            end

            suggestions += org_suggestions
          end

          if include_emus?
            user_suggestions = without_selected_values_users(users_suggestions_rel)
              .order(:login)
              .limit(limit)
              .map do |user|
                ::SecurityCenter::Suggestions::Suggestion.new(value: user.display_login, description: "User")
              end

            suggestions += user_suggestions
          end

          suggestions.take(limit)
        end

        sig { returns(T::Array[Organization]) }
        memoize def without_selected_values
          selected_values_set = Set.new(selected_values)

          authorized_orgs.reject { |o| selected_values_set.include?(o.display_login) }
        end

        sig { returns(ActiveRecord::Relation) }
        def users_suggestions_rel
          users_rel = if GitHub.enterprise?
            User
              .where(type: "User")
              .where.not(login: GitHub.ghost_user_login)
          else
            User.none unless business.enterprise_managed? && business.external_provider.present?
            BusinessUserAccount
              .where(business_id: business.id)
              .then do |rel|
                # While it may not be possible in production, 'find_first_emu_owner' is implemented in a way that
                # CAN return 'nil' thus we are doing proper type checking here.
                first_emu_owner = T.let(business.find_first_emu_owner, T.nilable(::User))
                next rel if first_emu_owner.nil?
                # Exclude the first EMU owner from the suggestions since this user is only used to setup idP and not part of external_identities
                rel.where.not(user_id: first_emu_owner.id)
              end
          end

          return User.none if users_rel.empty?
          return users_rel if value.blank?

          users_rel.where("login LIKE ?", "%#{value}%")
        end

        sig { params(users_rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def without_selected_values_users(users_rel)
          return users_rel if selected_values.blank?

          users_rel.where.not(login: selected_values)
        end

        sig { returns(T::Boolean) }
        memoize def include_emus?
          business_authz = ::SecurityProduct::Permissions::BusinessAuthz.new(business, actor: user)
          return false unless business_authz.can_view_user_owned_repository_alerts?
          AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
        end
      end
    end
  end
end
