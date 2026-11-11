# typed: strict
# frozen_string_literal: true

module Issues
  module IIssueField
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def owner_id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(String) }
    def name_slug; end

    sig { abstract.returns(T.nilable(String)) }
    def description; end

    sig { abstract.returns(User) }
    def owner; end

    sig { abstract.returns(String) }
    def data_type; end

    sig { abstract.returns(String) }
    def visibility; end

    sig { abstract.returns(T.nilable(Integer)) }
    def priority; end

    sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
    def to_json_react; end

    # Returns the time at which the IssueField was first persisted to the database.
    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def created_at; end

    # Returns if the IssueField is viewable by the given viewer.
    # This is used to filter issue fields that are only visible to organization members.
    # The logic is as follows:
    # - If the IssueField is public, it is viewable by everyone.
    # - If the IssueField is organization-only, it is viewable by organization members and
    #   outside collaborators on the specific repository (when repository_id is provided).
    #
    # @param viewer [User, nil] The user viewing the field.
    # @param repository_id [Integer, nil] The repository context for scoping collaborator access.
    #   When provided, outside collaborators on that repository can view org_only fields.
    #   When nil, only organization members can view org_only fields.
    sig { abstract.params(viewer: T.nilable(User), repository_id: T.nilable(Integer)).returns(T::Boolean) }
    def viewable_by?(viewer:, repository_id: nil); end
  end
end
