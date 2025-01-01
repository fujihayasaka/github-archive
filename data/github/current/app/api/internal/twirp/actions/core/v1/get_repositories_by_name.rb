# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetRepositoriesByName

        attr_reader :req, :env

        MAX_REPOSITORIES = 100

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          if req.nwos.empty?
            Twirp::Error.invalid_argument("must be non-empty", argument: "nwos")
          elsif req.nwos.size > MAX_REPOSITORIES
            Twirp::Error.invalid_argument("must have a length <= #{MAX_REPOSITORIES}", argument: "nwos")
          elsif GitHub.multi_tenant_enterprise? && !GitHub::CurrentTenant.get.present?
            Twirp::Error.failed_precondition("Tenant must be set in X-GitHub-Tenant header")
          else
            # Get unique repository nwos
            nwos = req.nwos.to_a.uniq

            # To minimize the number of lookups, group the raw NWOs we received by (raw) owner names.
            owner_to_repo_names = get_owner_to_repo_names_mapping(nwos)
            raw_owner_display_logins = owner_to_repo_names.keys

            # In a multi-tenant environment, the following User.Where call
            # pares the set of owners down to only those that belong to the CurrentTenant.
            # In other words, this is the mechanism that ensures we don't leak information about
            # repositories belonging to other tenants.
            # See class UserLoginType for an explanation of how where(login: ...)
            # is able to resolve both logins and (unsuffixed) display_logins.
            refined_owners = User.where(login: raw_owner_display_logins)

            repositories = []
            refined_owners.each do |owner|
              # In a multi-tenant environment, owner.login is decorated with the "tenant suffix" (short code),
              # so we use `owner.display_login` for apples-to-apples comparison with the raw owner name we were passed.
              repo_names = owner_to_repo_names[owner.display_login.downcase]
              repos = owner.repositories.where(name: repo_names)
              repositories.concat(repos)
            end

            create_response(nwos, repositories)
          end
        end

        private

        # Private: Gets a map of owner_login to repository names.
        #
        # nwos : array of full repository names
        #
        # Returns a hash of mapping owner_login => repository names.
        def get_owner_to_repo_names_mapping(nwos)
          owner_to_repo_names = {}

          nwos.each do |repo_nwo|
            owner_login, repo_name = repo_nwo.split("/")

            next unless repo_name && GitHub::UTF8.valid_unicode3?(repo_name.to_s)
            next unless owner_login && GitHub::UTF8.valid_unicode3?(owner_login.to_s)

            owner_login_downcase = owner_login.downcase
            if owner_to_repo_names.key?(owner_login_downcase)
              owner_to_repo_names[owner_login_downcase].push(repo_name)
            else
              owner_to_repo_names[owner_login_downcase] = [repo_name]
            end
          end

          owner_to_repo_names
        end

        # Private: Gets the visibility of the repository.
        #
        # Returns an enum.
        def get_repository_visibility(repository)
          if repository.public?
            :REPOSITORY_VISIBILITY_PUBLIC
          elsif repository.private? && repository.visibility == Repository::PRIVATE_VISIBILITY
            :REPOSITORY_VISIBILITY_PRIVATE
          elsif repository.internal?
            :REPOSITORY_VISIBILITY_INTERNAL
          else
            :REPOSITORY_VISIBILITY_INVALID
          end
        end

        # Private: Convert an array of Repository objects to the Twirp response FindRepositoriesByNameResponse.
        #
        # repositories - The array of Repository objects.
        # repositories_not_found_error_message - The error message to return if some repositories are found.
        #
        # Returns an array of Hash objects with repository data that matches the
        # Twirp definition.
        def create_response(nwos, repositories)
          # The nwos parameter passed to this method represents the raw nwos requested by the twirip caller,
          # so for apples-to-apples comparision, use repo.name_with_display_owner.
          repos_found = repositories.map { |repo| repo.name_with_display_owner.downcase }
          nwos_downcase = nwos.map(&:downcase)
          repos_not_found = nwos_downcase - repos_found

          repos_not_found_error_message = nil
          if repos_not_found.size > 0
            repos_not_found_error_message = "#{"Repository".pluralize(repos_not_found.count)} not found: #{repos_not_found.to_sentence}."
          end

          repositories_list = repositories.map do |repository|
            next {} unless repository
            {
              id: repository.id,
              name: repository.name,
              global_relay_id: get_global_id(repository),
              owner_login: repository.owner_display_login,
              visibility: get_repository_visibility(repository),
            }
          end

          {
            repositories: repositories_list,
            repositories_not_found_error_message: repos_not_found_error_message.nil? ? nil : repos_not_found_error_message.truncate(1_000),
          }
        end

        def get_global_id(repository)
          use_next_gid = !GitHub.enterprise?
          use_next_gid ? repository.next_global_id : repository.global_relay_id
        end
      end
    end
  end
end
