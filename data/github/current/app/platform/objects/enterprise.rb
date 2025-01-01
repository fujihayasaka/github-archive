# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Enterprise < Platform::Objects::Base
      model_name "Business"

      minimum_accepted_scopes ["read:enterprise"]

      description "An account to manage multiple organizations with consolidated policy and billing."

      implements_node templates: [[:e, :enterprise_id]], as: "E", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |enterprise|
        {
          prefix: :e,
          enterprise_id: enterprise.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.access_allowed?(:view_business_profile, resource: object, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer&.respond_to?(:site_admin?) && permission.viewer.site_admin?
        object.readable_by?(permission.viewer)
      end

      database_id_field

      created_at_field

      updated_at_field

      field :name, String, description: "The name of the enterprise.", null: false

      field :slug, String, description: "The URL-friendly identifier for the enterprise.", null: false

      field :description, String, description: "The description of the enterprise.", null: true

      field :description_html, Scalars::HTML, description: "The description of the enterprise as HTML.", null: false

      field :billing_email, String, description: "The enterprise's billing email.", null: true

      def billing_email
        visible = @object.owner?(@context[:viewer]) ||
          (@context[:viewer]&.respond_to?(:site_admin?) && @context[:viewer].site_admin?)
        return unless visible

        @object.billing_email
      end

      field :security_contact_email,
        String,
        description: "The enterprise's security contact email address.",
        null: true,
        visibility: { public: { environments: [:dotcom] } }

      def security_contact_email
        visible = @object.owner?(@context[:viewer]) ||
          (@context[:viewer]&.respond_to?(:site_admin?) && @context[:viewer].site_admin?)
        return unless visible

        @object.security_contact_email
      end

      def description_html
        if @object.description.present?
          GitHub::Goomba::ProfileBioPipeline.to_html(@object.description, {})
        else
          GitHub::HTMLSafeString::EMPTY
        end
      end

      field :readme, String, description: "The raw content of the enterprise README.", null: true

      def readme
        @object.long_description
      end

      field :readme_html, Scalars::HTML, description: "The content of the enterprise README as HTML.", null: false

      def readme_html
        if @object.long_description.present?
          @object.long_description_html
        else
          GitHub::HTMLSafeString::EMPTY
        end
      end

      field :website_url, Scalars::URI, description: "The URL of the enterprise website.", null: true

      field :location, String, description: "The location of the enterprise.", null: true

      url_fields description: "The HTTP URL for this enterprise." do |business|
        template = Addressable::Template.new("/enterprises/{slug}")
        template.expand slug: business.slug
      end

      field :avatar_url, Scalars::URI, description: "A URL pointing to the enterprise's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(**arguments)
        @object.primary_avatar_url(arguments[:size])
      end

      field :members, resolver: Resolvers::EnterpriseMembers, description: "A list of users who are members of this enterprise.", connection: true

      field :organizations, resolver: Resolvers::EnterpriseOrganizations, description: "A list of organizations that belong to this enterprise.", connection: true

      field :organizations_members, Connections.define(Objects::User), description: <<~DESCRIPTION, null: false, connection: true, visibility: :internal  do
          EnterpriseMembers across Organizations within a single Enterprise where the User is an Organization(s) Owner
        DESCRIPTION
        argument :phrase, String, "An optional search phrase to query for members across organizations", required: false
        argument :ids, [ID], "An optional list of User IDs to filter members by", required: false
      end

      def organizations_members(**arguments)
        Promise.all([@object.async_organizations, @object.async_customer]).then do
          # Enterprise owners, billing managers, and site admins should see all orgs
          is_enterprise_admin = @object.owner?(@context[:viewer]) || @object.billing_manager?(@context[:viewer])
          is_site_admin = @context[:viewer].site_admin?
          can_view_all_members = is_enterprise_admin || is_site_admin
          is_copilot_standalone = @object.is_copilot_standalone?

          filtered_organization_logins = if can_view_all_members
            nil # disable the org filter and show all orgs
          else
            @object.filtered_organizations(
              viewer_role: "owner",
              viewer: @context[:viewer],
            ).map(&:display_login)
          end

          if filtered_organization_logins.nil? || filtered_organization_logins.any?
            users = if arguments[:ids].present?
              arguments[:ids].map do |id|
                Helpers::NodeIdentification.async_typed_object_from_id(Objects::User, id, @context)
              end
            else
              []
            end

            if is_copilot_standalone
              scope = @object.filtered_members(
                @context[:viewer],
                query: arguments[:phrase],
                allow_filters_for_non_admin_viewer: true,
                include_unaffiliated: true,
                organization_logins: filtered_organization_logins,
              )
            else
              scope = @object.filtered_members(
                @context[:viewer],
                query: arguments[:phrase],
                allow_filters_for_non_admin_viewer: true,
                ignore_org_membership_visibility: can_view_all_members, # Enterprise owners, billing managers, and site admins see all members
                organization_logins: filtered_organization_logins,
              )
            end

            Promise.all(users).then do |users|
              if users.present?
                if GitHub.single_business_environment?
                  scope.where(id: users.map(&:id))
                else
                  scope.includes(:user).where(user_id: users.map(&:id)).map(&:user)
                end
              else
                scope = scope.includes(:user).map(&:user) unless GitHub.single_business_environment?
                scope
              end
            end
          else
            Platform::ArrayWrapper.new([])
          end
        end
      end

      field :user_namespace_repositories, resolver: Resolvers::EnterpriseUserNamespaceRepositories,
        minimum_accepted_scopes: ["admin:enterprise"],
        description: "A list of repositories that belong to users. Only available for enterprises with Enterprise Managed Users.",
        connection: true,
        visibility: { public: { environments: [:dotcom] } }

      field :viewer_is_admin, Boolean, null: false, description: "Is the current viewer an admin of this enterprise?"
      def viewer_is_admin
        @object.owner?(@context[:viewer])
      end

      field :owner_info, Objects::EnterpriseOwnerInfo,
            description: "Enterprise information visible to enterprise owners or enterprise owners' personal access tokens (classic) with read:enterprise or admin:enterprise scope.",
            null: true

      def owner_info
        return unless @object.owner?(@context[:viewer]) || (@context[:viewer]&.respond_to?(:site_admin?) && @context[:viewer].site_admin?)
        @object
      end

      field :billing_info, Objects::EnterpriseBillingInfo, description: "Enterprise billing information visible to enterprise billing managers.", null: true

      def billing_info
        return unless @object.owner?(@context[:viewer]) ||
          @object.billing_manager?(@context[:viewer]) ||
          (@context[:viewer]&.respond_to?(:site_admin?) && @context[:viewer].site_admin?)
        @object
      end

      field :stafftools_info,
        Objects::EnterpriseStafftoolsInfo,
        visibility: :internal,
        description: "Enterprise information only visible to site admins", null: true

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::AccountStafftoolsInfo.new(@object)
        else
          nil
        end
      end

      field :managed_type,
        Enums::EnterpriseManagedTypeValue,
        null: false,
        visibility: :internal,
        description: "The managed type of the enterprise."

      def managed_type
        if @object.enterprise_managed?
          return T.must(Enums::EnterpriseManagedTypeValue.values["ENTERPRISE_MANAGED"]).value
        end

        T.must(Enums::EnterpriseManagedTypeValue.values["DEFAULT_MANAGED"]).value
      end

      field :is_copilot_mobile_chat_enabled, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether Copilot Chat for Mobile is enabled for this enterprise", null: false

      def is_copilot_mobile_chat_enabled
        Copilot::Business.new(object).mobile_chat_enabled?
      end

      field :ruleset, Objects::RepositoryRuleset,
        minimum_accepted_scopes: ["admin:enterprise"],
        description: "Returns a single ruleset from the current enterprise by ID.",
        null: true do
          argument :database_id, Integer, "The ID of the ruleset to be returned.", required: true
        end

      def ruleset(**arguments)
        ::RepositoryRuleset.load_for(source: @object.is_a?(Platform::Models::Enterprise) ? @object.business : @object).find { |ruleset| ruleset.id == arguments[:database_id] }
      end

      field :rulesets, Platform::Connections::RepositoryRuleset,
        minimum_accepted_scopes: ["admin:enterprise"],
        description: "A list of rulesets for this enterprise.",
        null: true,
        connection: true

      def rulesets
        ArrayWrapper.new(::RepositoryRuleset.load_for(source: @object.is_a?(Platform::Models::Enterprise) ? @object.business : @object))
      end

      field :announcement_banner, Objects::AnnouncementBanner, description: "The announcement banner set on this enterprise, if any. Only visible to members of the enterprise.", null: true

      def announcement_banner
        EnterpriseBanner.find_by(owner: @object)
      end
    end
  end
end
