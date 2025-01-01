# typed: true
# frozen_string_literal: true

module CommandPalette
  class Context
    class Scope
      attr_reader :repository, :owner, :type, :object

      def initialize(object)
        case object
        when Repository
          @repository = object
          @owner = object.owner
        when User
          @repository = nil
          @owner = object
        else
          @repository = nil
          @owner = nil
        end

        @object = object
        @type = object.class
      end

      # Predicates

      # Overwiting this, affects how we calculate #present? for free
      def blank?
        object.nil?
      end

      def repository?
        repository.present?
      end

      def user?
        owner&.user? && !repository?
      end

      def organization?
        owner&.organization? && !repository?
      end

      def user_owned?
        owner&.user? && repository?
      end

      def organization_owned?
        owner&.organization? && repository?
      end

      # Special getters

      def user
        owner if user?
      end

      def organization
        owner if organization?
      end

      def user_owner
        owner if user_owned?
      end

      def organization_owner
        owner if organization_owned?
      end
    end

    attr_reader :current_user, :subject, :scope, :user_session, :cap_filter, :return_to

    def initialize(current_user:, subject: nil, scope: nil, user_session: nil, cap_filter: nil, return_to: nil)
      @current_user = current_user
      @subject = subject
      @scope = Scope.new(scope)
      @user_session = user_session
      @cap_filter = cap_filter
      @return_to = return_to
    end

    def current_user_affiliated_orgs
      @current_user_affiliated_orgs ||= current_user.affiliated_organizations_with_roles
    end
  end
end
