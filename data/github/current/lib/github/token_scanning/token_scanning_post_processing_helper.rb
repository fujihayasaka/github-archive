# typed: true
# frozen_string_literal: true

module GitHub
  module TokenScanning
    module TokenScanningPostProcessingHelper
      include GitHub::TokenScanning::SecretScanningHelper
      include GitHub::TokenScanning::TokenRevocationHelper
      include SecretScanning::Errors

      class TokenRemediation
        attr_accessor :remediation, :event_at

        def initialize(remediation = nil, event_at = nil)
          @remediation    = remediation
          @event_at       = event_at
        end
      end

      BUSINESSES_TO_REVOKE_KEYS_FROM = ["microsoftopensource"].freeze
      ORGS_TO_REVOKE_KEYS_FROM = ["github"].freeze

      sig { params(fingerprints: T::Hash[String, String], repo: T.nilable(T.any(Repository, Gist))).returns(T::Hash[String, String]) }
      private def add_tenant_shortcode!(fingerprints, repo)
        if GitHub.multi_tenant_enterprise? && repo.present? && repo.owner.present?
          shortcode = repo.owner.organization? ? repo.owner.business&.shortcode : repo.owner.enterprise_managed_business&.shortcode

          if shortcode.present?
            fingerprints.transform_values! { |v| "#{v}_#{shortcode}" }
          end
        end

        fingerprints
      end

      sig { params(tokens: T::Array[String], repo: T.nilable(T.any(Repository, Gist))).returns(T::Hash[String, String]) }
      def ssh_key_fingerprints(tokens, repo)
        fingerprints = tokens.each_with_object(Hash.new) do |token, fprs|
          next if fprs.key?(token)

          fprs[token] = begin
            SSHData::PrivateKey.parse(token).first.public_key.fingerprint
          rescue SSHData::Error => e
            {}
          end
        end

        # On Proxima, Public Keys are contextualized with the tenant shortcode
        # so we need to append the shortcode to fingerprints otherwise we won't find any matches
        add_tenant_shortcode!(fingerprints, repo)
      end

      def public_key_already_unverified?(public_key)
        !public_key.verified? &&
        (public_key.unverification_reason == "token_scan" || public_key.unverification_reason == "token_scan_revoked_by_user_in_private_repo")
      end

      def unverify_and_notify_public_key(public_key, token, target = nil, is_private_revoke = false, revoked_by: nil)
        public_key.unverify(is_private_revoke ? :token_scan_revoked_by_user_in_private_repo : :token_scan)

        # Send unique mailer for deploy keys.
        if public_key.repository_key?
          case token.token_source
          when :GIST
            RepositoryMailer.ssh_deploy_private_key_leaked_in_gist(public_key.repository, token.url).deliver_later
          when :CONTENT
            RepositoryMailer.ssh_deploy_private_key_leaked(public_key.repository, token.url).deliver_later
          when :WIKI_CONTENT
            RepositoryMailer.ssh_deploy_private_key_leaked_in_wiki(public_key.repository, token.url).deliver_later
          end
        else
          notify_user_of_revoked_access(
            target: target,
            user: public_key.owner,
            token: token,
            revoked_by: revoked_by,
            key_name: public_key.title,
            is_private_key: true,
            is_expired: false,
          )
        end
      end

      sig { params(fingerprints: T::Array[String]).returns(T::Hash[String, PublicKey]) }
      def public_keys_for_fingerprints(fingerprints)
        PublicKey.
          includes(:user, :repository).
          where(fingerprint_sha256: fingerprints).
          index_by(&:fingerprint_sha256)
      end

      sig { params(tokens: T::Array[GitHub::TokenScanning::FoundToken], target: T.nilable(T.any(Repository, Gist)), is_private_revoke: T::Boolean, revoked_by: T.nilable(User)).returns(T::Array[GitHub::TokenScanning::FoundToken]) }
      def revoke_github_ssh_private_keys(tokens, target, is_private_revoke = false, revoked_by: nil)
        pem_tokens = tokens.select { |t| %w(ARMORED_PEM_PRIVATE_KEY GITHUB_SSH_PRIVATE_KEY).include?(t.type) }

        fingerprints = ssh_key_fingerprints(pem_tokens.map(&:token), target)
        keys = public_keys_for_fingerprints(fingerprints.values.compact)

        pem_tokens.each do |token|
          fingerprint = T.must(fingerprints[token.token])

          key = keys[fingerprint]
          next if target&.private? && !(
            key_is_associated_with_github_or_microsoft(key) &&
            repo_is_associated_with_github_or_microsoft(target)
          ) && !is_private_revoke

          unverify_and_notify(token, key, target, is_private_revoke, revoked_by: revoked_by)
        end

        tokens
      end

      def key_is_associated_with_github_or_microsoft(key)
        if key.nil?
          return false
        end

        if key.user.present?
          # In case the key has "user" property, this is a personal SSH key
          # and we check for SSO authorization of that key
          key.active_org_credential_authorizations.map(&:organization).each do |org|
            return true if org_in_revocation_scope?(org)
          end
        elsif key.owner.organization?
          # In case the key's owner is organization it's the deployment key (not personal)
          # see https://docs.github.com/free-pro-team@latest/developers/overview/managing-deploy-keys#deploy-keys

          # There is a difference between a repo owner and a repo organization.
          # When a repo is forked, organization stays the old parent, but owner becomes the new repo's parent.
          # So we use repo owner.
          org = key.owner
          return true if org_in_revocation_scope?(org)
        end

        false
      end

      # Revoke ssh access and notify the owner.
      #
      # public_key - The PublicKey associated with this SSH token, if any.
      #
      # Returns nothing.
      def unverify_and_notify(token, public_key, target, is_private_revoke, revoked_by: nil)
        in_gist = target.is_a?(Gist)

        unless token.url.present?
          token.state = :no_url
          return
        end

        if public_key.nil?
          token.state = :no_public_key
          return
        end

        if public_key_already_unverified?(public_key)
          token.state = :already_unverified
          return
        end

        unverify_and_notify_public_key(public_key, token, target, is_private_revoke, revoked_by: revoked_by)
        token.state = :unverified
        token.mark_processed
      rescue => e # rubocop:todo Lint/GenericRescue
        token.error = e
        Failbot.report(e)
      end

      def with_read
        ActiveRecord::Base.connected_to(role: :reading) do
          yield
        end
      end

      # repository_id, in the case of wikis, will be the ID of the repo to which the wiki belongs
      # The returned repo is used by our dotcom API handlers to
      #  - get tenant shortcodes
      #  - see whether the user has read access to the repo
      #  - get the repo's owner for email and email settings
      sig { params(repository_type: T.any(Symbol, Integer), repository_id: Integer).returns(T.nilable(T.any(Repository, Gist))) }
      def get_repo_from_request(repository_type, repository_id)
        repo = nil
        if repository_type == :REPOSITORY || repository_type == :WIKI
          repo = ::Repositories::Public.find_active(repository_id)
        end

        if repository_type == :GIST
          repo = Gist.find_by(id: repository_id)
        end

        repo
      end
    end
  end
end
