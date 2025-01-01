# typed: true
# frozen_string_literal: true

module GitHub
  module Billing
    class OpenGitcoinIssue
      extend T::Sig

      GITCOIN_REPO_NWO = "github/gitcoin"
      GITCOIN_REPO_ID = 18689107
      ISSUE_LABELS = ["slack🧵"]

      # Public: Initialize a new command object
      #
      # title - The title that will be used to create the issue
      # description - The description that will be used to create the issue
      sig { params(title: T.nilable(String), description: T.nilable(String)).returns(T.nilable(Issue)) }
      def self.create(title, description)
        new(title, description).create
      end

      # Public: Initialize a new command object
      #
      # title - The title that will be used to create the issue
      # description - The description that will be used to create the issue
      sig { params(title: T.nilable(String), description: T.nilable(String)).void }
      def initialize(title, description)
        @title = title
        @description = description
      end

      # Public: Determines whether we will be able to create an issue by validating title and
      # description args are present and confirms we are able to find the gitcoin repo
      #
      # Returns true or false
      sig { returns(T::Boolean) }
      def valid?
        if [@title, @description].any?(&:blank?)
          Failbot.report(ArgumentError.new "title and description required")
          return false
        end

        return false unless repo
        return false unless gitcoin_repo?

        true
      end

      # Public: Creates a new gitcoin issue or returns nil if we can't
      #
      # Returns Issue or nil
      sig { returns(T.nilable(Issue)) }
      def create
        return unless valid?

        T.must(repo).issues.create!(user: User.staff_user,
                            repository_id: T.must(repo).id,
                            title: title,
                            body: description,
                            labels: labels)
      end

      private

      attr_reader :title, :description

      # Internal: This method will check if the gitcoin repo exists
      #
      # Returns true or false
      sig { returns(T::Boolean) }
      def gitcoin_repo?
        "#{T.must(repo).owner_display_login}/#{T.must(repo).name}" == GITCOIN_REPO_NWO
      end

      sig { returns(ActiveRecord::Relation) }
      def labels
        T.must(repo).labels.where(name: ISSUE_LABELS)
      end

      sig { returns(T.nilable(Repository)) }
      def repo
        @repo ||= Repositories::Public.find_active(GITCOIN_REPO_ID)
      end

    end
  end
end
