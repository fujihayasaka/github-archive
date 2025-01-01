# typed: true
# frozen_string_literal: true

module Platform
  module Security
    class RepositoryAccess
      extend T::Sig
      extend T::Generic
      include GitHub::ResilienceMixin

      Viewed = type_template

      KEY = :"#{name}.current"

      NO_REPOSITORIES = [].freeze

      sig { params(user: T.nilable(User), block: T.proc.returns(Viewed)).returns(Viewed) }
      def self.with_viewer(user, &block)
        previous = Thread.current[KEY]
        Thread.current[KEY] = new(user)

        # Theoretically, this isn't great, but we do get to eliminate a lot of `ignore_association_loads`
        # sprinkled in the code. By explicitly calling `async` then `sync`, we state that the
        # data has been preloaded, so any subsequent calls to `bot.integration` don't trip
        # `AssociationLoaded` errors. It's a nasty trick, but it's useful to do it once, here in the
        # beginning. We also can't call `async` here because we're not in a Promise-ified environment
        if user.is_a?(Bot) && user.installation
          user.installation.async_target.sync
        end

        yield
      ensure
        Thread.current[KEY] = previous
      end

      if Rails.env.test?
        # This is only required in test, where we need `.current` outside of graphql execution
        # Don't use it outside of test, since you could clobber a previous `.current`
        def self.ensure_viewer(user)
          Thread.current[KEY] = new(user)
        end
      end

      def self.current
        Thread.current[KEY] or raise Platform::Errors::Security, "No current Platform::Security::RepositoryAccess instance found."
      end

      # Sorbet understands this `class << self` syntax and Ruby should evaluate it as against the singleton_class
      class << self
        delegate \
          :async_guard,
          :async_permit_with_message,
          :accessible_repository_ids,
          to: :current
      end

      def initialize(user)
        @user = user
        @accessible_repository_ids = {}
      end

      # Apply a permission check to `repository`, and if the check fails, handle it according to `security_violation_behaviour`.
      # Usually, the violation behavior should be `:raise`. Only pass something else if you have other plans to handle unpermitted repos.
      def async_guard(repository, security_violation_behaviour:, security_unavailable_behavior: :raise, candidate_user_permission_check: false)
        async_permit_with_message_with_resilience(repository, security_unavailable_behavior, candidate_user_permission_check).then do |(has_permission, message)|
          if has_permission
            repository
          else
            case security_violation_behaviour
            when :raise
              message ||= "No explanation given."
              raise Platform::Errors::Security, <<~ERR
                Would have exposed Repository ##{repository.id}, Node ID #{repository.global_relay_id}.

                Reason: #{message}

                This repository should have been filtered out _before_ being returned to the viewer.
                It was caught at the last minute and the request was halted rather than returning data to the client.
                ERR
            when :nil
              nil
            when :allow
              repository
            else
              raise Platform::Errors::Internal, "Unknown security_violation_behaviour: #{security_violation_behaviour.inspect}"
            end
          end
        end
      end

      # Returns a promise that resolves to a two-item array, [is_permitted, denial_message].
      # If the repo is permitted, `denial_message` is nil.
      #
      # @param repository [::Repository]
      # @return [Promise<Array(Boolean, String)>]
      def async_permit_with_message(repository, candidate_user_permission_check = false)
        repository.async_hide_from_user?(@user).then do |is_hidden|
          if is_hidden
            [false, "Hidden from viewer"]
          elsif repository.access.disabled? && (@user.nil? || !@user.site_admin?)
            [false, "Access disabled"]
          elsif repository.public?
            [true, nil]
          elsif @user.nil?
            [false, "No viewer -- can't see private repo"]
          elsif GitHub.site_admin_can_see_private_repo? && @user.site_admin?
            [true, nil]
          else
            Promise.all([repository.async_internal_repository, @user.async_business_ids(valid_license: true)]).then do |internal_repository, business_ids|
              if internal_repository && business_ids.include?(internal_repository.business_id)
                [true, nil]
              else
                @user.async_associated_repository?(repository.id).then do |has_access|
                  if has_access
                    [true, nil]
                  else
                    promise = if candidate_user_permission_check
                      Platform::Loaders::Permissions::UserPermissionCheckCandidate.load(user: @user, target: repository, permission_name: "read_repo_contents")
                    else
                      Platform::Loaders::Permissions::UserPermissionCheck.load(user: @user, target: repository, permission_name: "read_repo_contents")
                    end
                    promise.then do |has_permission|
                      if has_permission
                        [true, nil]
                      else
                        @user.async_has_unlocked_repository?(repository).then do |has_unlocked|
                          if has_unlocked
                            [true, nil]
                          else
                            [false, "Repository is locked"]
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      def async_permit_with_message_with_resilience(repository, security_unavailable_behavior, candidate_user_permission_check)
        if security_unavailable_behavior == :filter
          with_async_database_error_fallback(
            async_permit_with_message(repository, candidate_user_permission_check),
            fallback: [false, "Error checking permissions"]
          )
        else
          async_permit_with_message(repository, candidate_user_permission_check)
        end
      end

      def accessible_repository_ids(repository_ids: nil)
        @accessible_repository_ids[repository_ids&.join(",")] ||=
          if @user
            @user.associated_repository_ids(repository_ids: repository_ids) | @user.unlocked_repository_ids
          else
            NO_REPOSITORIES
          end
      end
    end
  end
end
