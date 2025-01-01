# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class GpgSignatureRequest
    include ActiveModel::Validations

    COMMIT_MESSAGE_AUTHOR_REGEX = /\Aauthor ([^<]*)[ ]{0,1}<(.+)>/
    COMMIT_MESSAGE_TREE_REGEX = /\Atree (.+?)/
    COMMIT_MESSAGE_TAG_REGEX = /\Atag (.+?)/
    COMMIT_MESSAGE_TAGGER_REGEX = /\Atagger (.+?) <(.+)>/

    attr_reader :current_user, :message, :codespace_token, :parsed_token, :gpg

    validates :author, :codespace, :tree, presence: true
    validate :gpg_enabled
    validate :correct_user
    validate :has_single_author
    validate :commit_author_valid
    validate :codespace_active
    validate :message_not_a_tag
    validate :pushable_by_user

    # current_user - The user currently signed in
    # author       - A string representing the user authoring this git commit, example: "Monalisa Octocat <monalisa@github.com>"
    # message      - A string containing a git commit header, example:
    #  tree bc6312
    #  parent 6dbbfe
    #  author %{user} <%{email}> 1599572979 -0400
    #  committer GitHub <noreply@github.com> 1599572979 -0400
    #
    #  testing x1
    #
    #  author by someone and <monalisa@github.com>
    #
    #  Co-authored-by: Codespace Guest <guest@example.com>
    #
    # Returns a token String.
    def initialize(current_user:, message:, codespace_token:, gpg: GitHub.gpg)
      @current_user = current_user
      @message = message.to_s
      @codespace_token = codespace_token
      @parsed_token = GitHub::Authentication::SignedAuthToken.verify(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, token: codespace_token.to_s)
      @gpg = gpg
    end

    def sign
      sign!
    rescue ActiveModel::ValidationError
      nil
    end

    def sign!
      validate! && gpg.sign(message)
    end

    def codespace
      return @codespace if defined?(@codespace)

      if parsed_token.data.present? && id = parsed_token.data["id"]
        @codespace = Codespace.find_by(id: id)
      else
        @codespace = nil
      end
    end

    def author
      return @author if defined?(@author)

      author_references = header_lines.grep(COMMIT_MESSAGE_AUTHOR_REGEX)
      if author_references.one?
        @author = author_references.first
      else
        @author = nil
      end
    end

    def tree
      return @tree if defined?(@tree)

      @tree = header_lines.grep(COMMIT_MESSAGE_TREE_REGEX).first
    end

    private

    def header_lines
      return @header_lines if defined?(@header_lines)

      @header_lines = message.split("\n").take_while { |line| line.present? }
    end

    # Refuse to sign any commit with a hint of multiple authors.
    # Git doesn't support multi-author commits by default per #git-systems.
    #
    # Our regex catches this in the happy case, but we've had folks sneak past
    # it before (see https://github.com/github/codespaces/issues/19407) so we
    # also do this more obviously correct check for multi-author separately.
    def has_single_author
      errors.add(:author, :multiple) if header_lines.many? { |line| line.start_with?("author ") }
    end

    def commit_author_valid
      return if author.blank?

      git_username, git_email = User.git_author_info(current_user)
      possible_emails         = [git_email].union(current_user.author_emails)
      match_data = author.match(COMMIT_MESSAGE_AUTHOR_REGEX)
      return if match_data[1]&.strip == git_username && possible_emails.include?(match_data[2])
      errors.add(:author, :invalid)
    end

    def gpg_enabled
      if current_user.gpg_authorization == Configurable::GpgAuthorization::DISABLED
        errors.add(:current_user, "GPG signing disabled")
      elsif current_user.gpg_authorization == Configurable::GpgAuthorization::SELECTED_REPOSITORIES || current_user.codespaces_repository_authorization == Configurable::CodespacesRepositoryAuthorization::SELECTED_REPOSITORIES
        errors.add(:current_user, "GPG signing not enabled on this repository") unless current_user.trusted_repository_authorizations.find_by(repository: codespace&.repository)
      end
    end

    def correct_user
      errors.add(:current_user, "is not the correct user") unless parsed_token.user == current_user
    end

    def codespace_active
      return unless codespace

      # Allow GPG signing while a codespace is spinning up so that we can sign initial git commits while reinitializing
      # git in a codespace template.
      return if codespace.requires_git_reinit? && (codespace.pending? || codespace.provisioning?)

      # Only sign GPG requests for codespaces that are consuming compute
      errors.add(:codespace, "must be running") unless codespace.consuming_compute?
    end

    def message_not_a_tag
      if header_lines.grep(COMMIT_MESSAGE_TAG_REGEX).present? || header_lines.grep(COMMIT_MESSAGE_TAGGER_REGEX).present?
        errors.add(:message, "contains tag fields")
      end
    end

    def pushable_by_user
      return unless current_user.oauth_access&.installation

      codespace = Codespace.find_by(id: current_user.oauth_access&.installation.codespace_ids.first)
      if !T.cast(codespace&.repository, T.nilable(Repository))&.pushable_by?(current_user) # rubocop:todo GitHub/AvoidCast
        errors.add(:current_user, "User does not have push access to this repository")
      end
    end
  end
end
