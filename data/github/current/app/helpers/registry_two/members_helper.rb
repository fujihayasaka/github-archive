# typed: false
# frozen_string_literal: true

module RegistryTwo
  module MembersHelper
    include ActiveSupport::Concern

    SUPPORTED_V2_ECOSYSTEMS = %w(
      container
      maven
      npm
      nuget
      rubygems
    )

    NON_CONTAINER_V2_ECOSYSTEMS = SUPPORTED_V2_ECOSYSTEMS - ["container"]

    SUPPORTED_V2_ECOSYSTEMS_SYM = SUPPORTED_V2_ECOSYSTEMS.map(&:to_sym)

    BILLED_V2_ECOSYSTEMS = %w(
      maven
      npm
      nuget
      rubygems
    )

    DEFAULT_PACKAGE_VERSIONS_LIMIT = 10
    DEFAULT_TAGGED_PACKAGE_VERSIONS_LIMIT = 5

    # Returns: { User/Team => Role}
    def members_to_roles
      return @members_to_roles if defined?(@members_to_roles)

      package_roles = Role.system_package_roles.to_a
      package_admin_role = package_roles.select { |r| r.name == "package_admin" }

      visible_teams = if package.owner.is_a?(Organization)
        package.owner.visible_teams_for(current_user)
      else
        []
      end

      @members_to_roles = UserRole.where(role_id: package_roles.map(&:id))
                                  .where(target_type: "Package", target_id: package.id)
                                  .includes(:actor)
                                  .select { |ur| ur.actor.present? && user_can_see_member?(visible_teams, ur.actor) }
                                  .map { |ur| [ur.actor, ur.role] }
      @members_to_roles.to_h
    end

    def user_can_see_member?(visible_teams, member)
      return true unless package.owner.is_a?(Organization)
      return true unless member.is_a?(Team)
      visible_teams.include?(member)
    end

    def package(namespace = owner&.login)
      return nil unless namespace
      @package ||= if supported_v2_ecosystem(params[:ecosystem])
        begin
          resp = client.get_package_metadata(
            namespace: owner.display_login,
            name: params[:name],
            ecosystem: params[:ecosystem],
            actor: current_user,
            version_limit: DEFAULT_PACKAGE_VERSIONS_LIMIT,
            include_deleted: action_name == "restore", # For restore, we need to find a deleted package.
            include_download_count: true
          )

          resp.try(:package)
        rescue PackageRegistry::Twirp::ServiceUnavailableError => e
          GitHub.logger.error(e)
        rescue PackageRegistry::Twirp::BaseError => e
          GitHub.logger.error(e)
          # explicit nil to ensure we don't set @package to whatever self.log returns
          nil
        end
      else
        owner.packages.find_by!(package_type: params[:ecosystem], name: params[:name])
      end
    end

    def supported_v2_ecosystem(ecosystem)
      SUPPORTED_V2_ECOSYSTEMS.include?(ecosystem)
    end

  end
end
