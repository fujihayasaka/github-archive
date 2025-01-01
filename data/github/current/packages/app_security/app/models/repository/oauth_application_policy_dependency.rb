# typed: true
# frozen_string_literal: true

module Repository::OauthApplicationPolicyDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  class_methods do
    # Public: Limit a list of repositories to those where the given OAuth
    # application meets the repository's OAuth application access policy.
    #
    # app              - OauthApplication
    # repository_ids   - Array<Integer> of repository ids
    # repository_scope - ActiveRecord::Relation instance providing repository scope
    #
    # The method can be called with both or either of `repository_ids` and `repository_scope`.
    # The result will take both inputs into account.
    #
    # Return Array<Integer> of repository ids
    def oauth_app_policy_approved_repository_ids(app:, repository_ids: [], repository_scope: nil)
      return [] if repository_ids.empty? && repository_scope.nil?
      if app.oap_exempt?
        additional_repository_ids = repository_scope&.ids || []
        return repository_ids + additional_repository_ids
      end

      return [] if repository_ids.empty?

      OauthApplicationPolicy.new(app, repository_ids, repository_scope).load_satisfied_repo_ids
    end

    # Public: Limit a list of repositories to those where the given OAuth
    # application meets the repository's OAuth application access policy.
    #
    # app              - OauthApplication
    # repository_ids   - Array<Integer> of repository ids
    # repository_scope - ActiveRecord::Relation instance providing repository scope
    #
    # The method can be called with both or either of `repository_ids` and `repository_scope`.
    # The result will take both inputs into account.
    #
    # This method is the equivalent to `.oauth_app_policy_approved_repository_ids` but it returns
    # an ActiveRecord scope instead of an array of ids.
    #
    # Return ActiveRecord::Relation
    def oauth_app_policy_approved_repository_scope(app:, repository_ids: [], repository_scope: nil)
      T.bind(self, T.class_of(Repository))

      return none if repository_ids.empty? && repository_scope.nil?

      if app.oap_exempt?
        if repository_ids.empty?
          return repository_scope || none
        else
          return where(id: repository_ids).merge(repository_scope)
        end
      end

      return where(id: OauthApplicationPolicy.new(app, repository_scope.pluck(:id), nil).load_satisfied_repo_ids) if repository_ids.empty?

      where(id: OauthApplicationPolicy.new(app, repository_ids, repository_scope).load_satisfied_repo_ids)
    end

    # Public: Limit a list of repositories to those where the given OAuth
    # application is blocked by the repository's OAuth application access policy.
    #
    # app              - OauthApplication
    # repository_ids   - Array<Integer> of repository ids
    # repository_scope - ActiveRecord::Relation instance providing repository scope
    #
    # The method can be called with both or either of `repository_ids` and `repository_scope`.
    # The result will take both inputs into account.
    #
    # Return Array<Integer> of repository ids
    def oauth_app_policy_violated_repository_ids(app:, repository_ids: [], repository_scope: nil)
      return [] if repository_ids.empty? && repository_scope.nil?
      return [] if app.oap_exempt?

      OauthApplicationPolicy.new(app, repository_ids, repository_scope).load_violated_repo_ids
    end

    # Public: Limit a list of repositories to those where the given OAuth
    # application is blocked by the repository's OAuth application access policy.
    #
    # app              - OauthApplication
    # repository_ids   - Array<Integer> of repository ids
    # repository_scope - ActiveRecord::Relation instance providing repository scope
    #
    # The method can be called with both or either of `repository_ids` and `repository_scope`.
    # The result will take both inputs into account.
    #
    # This method is the equivalent to `.oauth_app_policy_violated_repository_ids` but it returns
    # an ActiveRecord scope instead of an array of ids.
    #
    # Return ActiveRecord::Relation
    def oauth_app_policy_violated_repository_scope(app:, repository_ids: [], repository_scope: nil)
      T.bind(self, T.class_of(Repository))

      return none if repository_ids.empty? && repository_scope.nil?
      return none if app.oap_exempt?

      where(id: OauthApplicationPolicy.new(app, repository_ids, repository_scope).load_violated_repo_ids)
    end
  end

  class OauthApplicationPolicy
    attr_reader :oauth_application, :repository_ids, :repository_data

    def initialize(oauth_application, repository_ids = nil, repository_scope = nil)
      raise ArgumentError, "OAuth application required" if oauth_application.nil?

      @oauth_application = oauth_application
      @repository_ids = repository_ids

      @repository_data = RepositoryData.new(oauth_application, repository_ids, repository_scope)
    end

    def load_satisfied_repo_ids
      repository_data.load

      repository_data.each_with_object([]) do |repo_hash, approved_repo_ids|
        approved_repo_ids << repo_hash[:id] if satisfied_repo?(repo_hash)
      end
    end

    def load_violated_repo_ids
      repository_data.load

      repository_data.each_with_object([]) do |repo_hash, violated_repo_ids|
        violated_repo_ids << repo_hash[:id] unless satisfied_repo?(repo_hash)
      end
    end

    private

    # Allow repositories when:
    #
    # If the repo is private:
    # - network owner is the oauth app's owner
    # - network owner is a user (not an organization) and:
    #   - the repository owner is a user (not an organization)
    #   - the repository owner doesn't restrict apps
    #   - the repository owner *does* restrict apps, and there's an authorization
    # - network owner is an organization and:
    #   - the network owner doesn't restrict apps, the repository owner does restrict, and the repo owner authorized the app
    #   - the network owner does restrict apps, the repository owner doesn't restrict, and the network owner authorized the app
    #   - the network owner and the repository don't restrict apps
    # If the repo is public:
    # - repository owner is the oauth app's owner
    # - repository owner is a user (not an organization)
    # - repository owner is an organization and:
    #   - the repository owner doesn't restrict apps
    #   - the repository owner *does* restrict apps, and there's authorization
    def satisfied_repo?(repo_hash)
      if !repo_hash[:public]
        if repo_hash[:network_root_owner_id] == oauth_application.user_id
          return true
        end

        case repo_hash[:network_root_owner_type]
        when "User"
          repo_hash[:owner_type] == "User" ||
            !repo_hash[:owner_restrict_oauth_apps] ||
            repo_hash[:owner_has_approved_app]
        when "Organization"
          if repo_hash[:owner_restrict_oauth_apps] && repo_hash[:network_root_owner_restrict_oauth_apps]
            repo_hash[:owner_has_approved_app] &&
              repo_hash[:network_root_owner_has_approved_app]
          elsif repo_hash[:owner_restrict_oauth_apps] && !repo_hash[:network_root_owner_restrict_oauth_apps]
            repo_hash[:owner_has_approved_app]
          elsif !repo_hash[:owner_restrict_oauth_apps] && repo_hash[:network_root_owner_restrict_oauth_apps]
            repo_hash[:network_root_owner_has_approved_app]
          else
            true
          end
        else
          false
        end
      else
        if repo_hash[:owner_id] == oauth_application.user_id
          return true
        end

        case repo_hash[:owner_type]
        when "User"
          true
        when "Organization"
          !repo_hash[:owner_restrict_oauth_apps] ||
            repo_hash[:owner_has_approved_app]
        else
          false
        end
      end
    end

    class RepositoryData
      include Enumerable
      include Scientist

      attr_reader :oauth_application, :repository_ids, :repository_scope,
                  :repo_data, :user_data_by_id, :approved_organization_owner_ids

      def initialize(oauth_application, repository_ids, repository_scope)
        @oauth_application = oauth_application
        @repository_ids = repository_ids
        @repository_scope = repository_scope
      end

      def blockable_app?
        return @blockable_app if defined?(@blockable_app)
        @blockable_app = oauth_application.blockable_client_app?
      end

      def each(&block)
        repo_data.each do |id, public, owner_id, network_root_owner_id|
          _, owner_type, owner_restrict_oauth_apps = user_data_by_id[owner_id]
          _, network_root_owner_type, network_root_owner_restrict_oauth_apps = user_data_by_id[network_root_owner_id]
          owner_has_approved_app = approved_organization_owner_ids.include?(owner_id)
          network_root_owner_has_approved_app = approved_organization_owner_ids.include?(network_root_owner_id)

          data = {
            id: id,
            public: public,
            owner_id: owner_id,
            owner_type: owner_type,
            owner_restrict_oauth_apps: owner_restrict_oauth_apps,
            owner_has_approved_app: owner_has_approved_app,
            network_root_owner_id: network_root_owner_id,
            network_root_owner_type: network_root_owner_type,
            network_root_owner_restrict_oauth_apps: network_root_owner_restrict_oauth_apps,
            network_root_owner_has_approved_app: network_root_owner_has_approved_app,
          }

          yield data
        end
      end

      def load
        @repo_data = load_repository_data_for(repository_ids, repository_scope)
        @user_data_by_id = load_user_data_for(repo_data)
        @approved_organization_owner_ids = load_approved_organization_owner_ids(user_data_by_id.values)
      end

      def load_repository_data_for(repository_ids, repository_scope)
        scope = Repository.joins(<<~SQL)
          INNER JOIN `repository_networks` ON `repository_networks`.`id` = `repositories`.`source_id`
          INNER JOIN `repositories` AS `root_repositories` ON `root_repositories`.`id` = `repository_networks`.`root_id`
        SQL
        scope = scope.merge(repository_scope) if repository_scope

        T.unsafe(scope).batched_scope(:id, values: repository_ids).pluck(Arel.sql(
          "`repositories`.`id`, `repositories`.`public`, `repositories`.`owner_id`, `root_repositories`.`owner_id`",
        ))
      end

      def load_user_data_for(repo_data)
        all_owner_ids = repo_data.each_with_object(Set.new) do |(_, _, owner_id, network_root_owner_id), result|
          result << owner_id << network_root_owner_id
        end

        User.where(id: all_owner_ids).pluck(:id, :type, :restrict_oauth_applications).index_by(&:first)
      end

      def load_approved_organization_owner_ids(user_data)
        all_organization_owner_ids = user_data.each_with_object([]) do |(id, type, _), result|
          result << id if type == "Organization"
        end

        if blockable_app?
          if FeatureFlag.vexi.enabled?(:load_approved_orgs_first_party_oap, default: false)
            all_org_ids = all_organization_owner_ids.to_set

            return all_org_ids unless FeatureFlag.vexi.exists_or_raise?(:first_party_oauth_app_restrictions) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

            # orgs 1st party app blocks is enabled for
            actor_ids_by_class = GitHub::VexiActor.actor_ids_by_class_or_raise(:first_party_oauth_app_restrictions)

            if FeatureFlag.vexi.enabled?(:consider_business_oap_ff, default: false)
              feature_businesses = actor_ids_by_class.to_h[Business] || []
              feature_business_org_ids = Business.where(id: feature_businesses).joins(:organization_memberships).pluck(:organization_id)

              feature_orgs = actor_ids_by_class.to_h[Organization] || []
              feature_orgs = (feature_orgs + feature_business_org_ids).uniq
            else
              feature_orgs = actor_ids_by_class.to_h[Organization] || []
            end

            return all_org_ids if feature_orgs.blank?

            feature_enabled_org_ids = feature_orgs.compact.map(&:to_i)
            org_ids_that_can_block = feature_enabled_org_ids & all_organization_owner_ids
            return all_org_ids if org_ids_that_can_block.empty?

            # orgs that actually block from list
            blocking_org_ids = OauthApplicationApproval.where(
              organization_id: org_ids_that_can_block,
              application_id: oauth_application,
              state: :blocked,
            ).pluck(:organization_id)

            # exclude orgs that block app
            org_ids = all_organization_owner_ids - blocking_org_ids
            org_ids.to_set
          else
            all_organization_owner_ids.to_set
          end
        else
          OauthApplicationApproval.where(
            organization_id: all_organization_owner_ids,
            application_id: oauth_application,
            state: :approved,
          ).pluck(:organization_id).to_set
        end
      end
    end
  end

  # Public: Return the user or organization that sets the security policies for
  # the repository.
  #
  # Returns a User or Organization.
  def policymaker
    return owner if public?
    return owner if !fork? # private root
    return owner if owner&.organization? && network_owner&.user? # org-owned private fork of user root
    return owner if owner&.restricts_oauth_applications? && !network_owner.restricts_oauth_applications?

    network_owner
  end
end
