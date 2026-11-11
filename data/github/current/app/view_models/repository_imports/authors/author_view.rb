# typed: true
# frozen_string_literal: true

module RepositoryImports
  module Authors
    class AuthorView < ::RepositoryImports::ShowView
      # Public: The repository for this view.
      #
      # Returns a Repository.
      attr_reader :repository

      # Public: The author for this view.
      #
      # Returns a RepositorySourceImport::Author.
      attr_reader :author

      # Public: The github User the author is mapped to.
      #
      # Returns a User or nil.
      def user
        @user ||= User.find_by_login(author.display_login) if author.display_login.present?
      end

      # Public: Is this author already mapped to a github user?
      #
      # Returns true or false.
      def mapped_to_github_user?
        user.present?
      end

      # Public: Has the author been mapped at all?
      #
      # Returns true or false.
      def author_mapped?
        author.email.present?
      end

      # Public: Does the mapped github user have an attributable email address?
      # It must be a public email on their github profile or they need to have
      # selected the keep my email address private option in their email
      # settings.
      #
      # Returns true or false.
      def has_attributable_email?
        has_profile_email? || has_stealth_email?
      end

      # Public: Will commit attribution fail for this author based on who they
      # are mapped to?
      #
      # Returns true or false.
      def has_problem?
        if user
          !has_attributable_email?
        else
          false
        end
      end

      # Public: Does the mapped github user have a public emali on their github
      # profile?
      #
      # Returns true or false.
      def has_profile_email?
        user && user.profile && user.profile.email.present?
      end

      # Public: Does the mapped github user have a stealth email? Currently
      # only created if the user selects the keep me email address private
      # option in their email settings.
      #
      # Returns true or false.
      def has_stealth_email?
        user && user.emails.any?(&:stealth?)
      end

      # Public: The author name. For an author mapped to a github user it tries
      # their public profile name first. If the author has not been mapped to a
      # github user it uses the name manually set for that author or defaults
      # back to the remote name found at the time of import.
      #
      # Returns a String.
      def author_name
        return user.name if user
        author.name || author.remote_name
      end

      # Public: The author email to display. If mapped to a github user it uses
      # their public attribution email. Otherwise it tries the manually set
      # email of the author or defaults back to the remote id found at the time
      # of import.
      #
      # Returns a String.
      def author_email
        if user
          user.public_attribution_email
        else
          author.email || author.remote_id
        end
      end

      # Public: The string to search author suggestions with. For an author
      # mapped to a github user it uses their login. Otherwise defaults to
      # the author_email above.
      #
      # Returns a String.
      def author_search_value
        if user
          user.display_login
        else
          author_email
        end
      end

      # Public: The url helper parameters for the author update form.
      #
      # Returns a Hash.
      def author_url_params
        url_params.merge(id: author.id)
      end
    end
  end
end
