# typed: true
# frozen_string_literal: true

module ProgrammaticAccessWithGrantAndToken
  class Creator
    include ActiveModel::Model

    attr_accessor :actor, :target, :access_token_attributes,
                  :permissions, :repositories, :repository_selection, :request_reason, :entry_point

    attr_reader :access, :grantable, :token_result

    def initialize(attributes = {})
      super
      @access_token_attributes ||= {}
    end

    # Public: Create a UserProgrammaticAccess with its associated UserProgrammaticAccessGrant, Permissions
    # and Authnd Token
    #
    # actor                   - The User performing the create operation
    # target                  - The targeted User
    # access_token_attributes - The Hash of attributes needed to create the UserProgrammaticAccess,
    #                           check ProgrammaticAccess.new_access for the expected signature
    # permissions             - A Hash indicating the requested set of permissions
    # repositories            - An array of Repositories the UserProgrammaticAccess will have access to
    # repository_selection    - A String. One of :all, :subset, or :none
    def self.perform(attributes)
      new(attributes).perform
    end

    def perform
      perform_with_transaction!
    rescue ActiveRecord::RecordNotUnique => e
      # A very small number of users experience a race condition when creating a token.
      # These don't get a validation error but a unique constraint violation.
      #
      # See https://github.com/github/ecosystem-apps/issues/2570 for more details.
      self.errors.add(:base, :write_failed, message: "A token with this name was recently created")
      self
    rescue ActiveRecord::ActiveRecordError => e
      self.errors.merge!(@access.errors)
      self.errors.merge!(@grantable.errors) if @grantable

      if self.errors.none?
        Failbot.report!(e)
        self.errors.add(:base, :write_failed, message: "an unknown error has occurred, please try again")
      end

      self
    end

    private

    def perform_with_transaction!
      @access = ProgrammaticAccess.new_access(actor, access_token_attributes)

      @access.set_expiration(
        access_token_attributes[:default_expires_at],
        access_token_attributes[:custom_expires_at]
      )

      if @access.errors.any?
        raise ActiveRecord::RecordNotSaved, "Unable to set token expiration"
      end

      ApplicationRecord::Permissions.transaction do
        ProgrammaticAccessBot.transaction do
          @access.save!

          @grantable = ProgrammaticAccessGrantRequest.create(
            access: access,
            actor: actor,
            permissions: permissions,
            repositories: repositories,
            repository_selection: repository_selection,
            request_reason: request_reason,
            target: target,
            entry_point: entry_point,
          )

          raise ActiveRecord::RecordNotSaved, "Unable to generate token grant" if @grantable.errors.any?

          # Attempt to "auto-approve" if @grantable is a request.
          if @grantable.approvable_by?(actor)
            @grantable = ProgrammaticAccessGrantRequest.approve(@grantable, actor, skip_approval_notification: true, entry_point: entry_point)
            raise ActiveRecord::RecordNotSaved, "Unable to generate token grant" if @grantable.errors.any?
          end
        end
      end

      @token_result = ProgrammaticAccessToken.generate(
        @access,
        expires_at: @access.expires_at,
      )

      @access.instrument_creation(@token_result)
      @access.notify_owner(about: :created)

      self
    end
  end
end
