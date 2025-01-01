# typed: true
# frozen_string_literal: true

module GitHub
  module TokenScanning
    module TokenRevocationHelper
      include GitHub::TokenScanning::SecretScanningHelper

      TOKEN_BATCH_SIZE = 100
      BUSINESSES_TO_REVOKE_KEYS_FROM = ["microsoftopensource"].freeze
      ORGS_TO_REVOKE_KEYS_FROM = ["github"].freeze

      def revoke_github_oauth_keys(tokens, target, is_one_click_revoke = false, revoked_by: nil, entry_point:)
        is_gist = target.present? && target.is_a?(Gist)

        # filter non-github access tokens
        # group by where they are stored in the database
        github_tokens = select_and_group_github_tokens(tokens)

        if github_tokens[oauth_access_type]&.any?
          oauth_accesses = for_oauth_tokens(github_tokens[oauth_access_type].map(&:token))

          revoked_oauth_access_seen = Set.new

          github_tokens[oauth_access_type].each do |token|
            oauth_access = oauth_accesses[token.token]

            if !token.url.present? && !is_one_click_revoke
              token.state = :no_url
              next
            end

            if oauth_access.nil?
              token.state = :no_oauth_access
              next
            end

            next unless target_in_revocation_scope?(target:, is_one_click_revoke:, oauth_access:)

            unless revoked_oauth_access_seen.include?(oauth_access.hashed_token)
              oauth_access.destroy_with_explanation(
                is_one_click_revoke ? :token_scan_revoked_by_user_in_private_repo : :token_scan,
                entry_point: entry_point,
              )
            end

            token.state = :revoked

            begin
              unless revoked_oauth_access_seen.include?(oauth_access.hashed_token)
                if !is_one_click_revoke
                  notify_user_of_revoked_access(
                    target: target,
                    user: oauth_access.user,
                    token: token,
                    app_name: get_app_name_for_access(oauth_access),
                    revoked_by: revoked_by,
                    is_expired: oauth_access.expired?,
                    key_name: oauth_access.description,
                  )
                end

                revoked_oauth_access_seen << oauth_access.hashed_token
              end
              token.mark_processed
            rescue => e # rubocop:todo Lint/RescueException
              token.error = e
              Failbot.report(e)
            end
          end
        end

        if github_tokens[refresh_token_type]&.any?
          # Missing:
          # * Destroying with an explanation
          # * Determining if token belongs to GitHub/Microsoft repo
          # * Determining who to send an email to
          #   * Ensuring that the user has access to the repo
          refresh_tokens = for_refresh_tokens(github_tokens[refresh_token_type].map(&:token))

          github_tokens[refresh_token_type].each do |token|
            refresh_token = refresh_tokens[token.token]

            if !token.url.present? && !is_one_click_revoke
              token.state = :no_url
              next
            end

            if refresh_token.nil?
              token.state = :no_oauth_access
              next
            end

            next unless target_in_revocation_scope?(target:, is_one_click_revoke:, oauth_access: nil)

            refresh_token.destroy
            token.state = :revoked

            if !is_one_click_revoke
              notify_user_of_revoked_access(
                target: target,
                user: refresh_token.refreshable.user,
                token: token,
                app_name: get_app_name_for_access(refresh_token.refreshable),
                revoked_by: revoked_by,
                is_expired: refresh_token.expired?,
              )
            end

            token.mark_processed
          end
        end

        if github_tokens[authentication_token_type]&.any?
          # Missing:
          # * Destroying with an explanation
          # * Determining if token belongs to GitHub/Microsoft repo
          # * Determining who to send an email to
          #   * Ensuring that the user has access to the repo
          authentication_tokens = for_authentication_tokens(github_tokens[authentication_token_type].map(&:token))

          github_tokens[authentication_token_type].each do |token|
            authentication_token = authentication_tokens[token.token]

            unless token.url.present?
              token.state = :no_url
              next
            end

            if authentication_token.nil?
              token.state = :no_oauth_access
              next
            end

            next unless target_in_revocation_scope?(target:, is_one_click_revoke:, oauth_access: nil)

            ServerToServerTokens.domain.destroy(authentication_token.id)
            token.state = :revoked

            users = []
            authenticatable = authentication_token.authenticatable_class.find_by(id: authentication_token.authenticatable_id)

            if authenticatable.nil?
              token.mark_processed
              next
            end

            app_integration = authenticatable.integration
            app_owner = app_integration.owner
            if app_owner.user?
              users << app_owner.id
            else
              potential_users = []

              potential_users += Apps::ManagementHelper.user_ids_with_app_owner_role(on: app_integration)
              potential_users += Apps::ManagementHelper.user_ids_with_app_manager_role(on: app_owner)

              app_owner.members(actor_ids: potential_users).each do |member|
                users << member.id
              end
            end

            users.each do |user_id|
              if !is_one_click_revoke
                notify_user_of_revoked_access(
                  target: target,
                  user: User.find(user_id),
                  token: token,
                  app_name: app_integration.name,
                  revoked_by: revoked_by,
                  is_expired: authentication_token.expires_at_timestamp.to_i < Time.now.to_i,
                )
              end
            end

            token.mark_processed
          end
        end

        tokens
      end

      def notify_user_of_revoked_access(
        target:,
        user:,
        token:,
        is_expired:,
        revoked_by:,
        app_name: nil,
        key_name: nil,
        is_private_key: false)
        is_gist = target.present? && target.is_a?(Gist)
        # Only include the URL if the repository is readable by the user
        # so private repository links are not leaked to users without access
        url = token.url if target.present? && target.readable_by?(user)
        if is_gist
          # Need to set source to :GIST because it's otherwise :CONTENT
          token.set_token_source(:GIST)
        end

        # we dont send emails for expired tokens to owners when they cannot access the repo.
        if url.nil? && is_expired
          return
        end

        skip_user_email = revoked_by.present? && user.present? && revoked_by.id == user.id
        if !skip_user_email
          if is_private_key
            SecretScanningMailer.ssh_private_key_leaked(target, user, token.token_source, url, key_name: key_name).deliver_later
          else
            if token.type.present?
              case token.type
              when "GITHUB", "GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_TOKEN_V2"
                SecretScanningMailer.personal_access_token_leaked(target, user, token.token_source, url, token_type: token.type, key_name: key_name).deliver_later
              when "GITHUB_OAUTH_ACCESS_TOKEN"
                SecretScanningMailer.oauth_app_user_access_token_leaked(target, user, token.token_source, url, token_type: token.type, app_name: app_name).deliver_later
              when "GITHUB_REFRESH_TOKEN", "GITHUB_USER_TO_SERVER_TOKEN"
                SecretScanningMailer.github_app_user_access_token_leaked(target, user, token.token_source, url, token_type: token.type, app_name: app_name).deliver_later
              when "GITHUB_SERVER_TO_SERVER_TOKEN", "GITHUB_APP_TOKEN"
                SecretScanningMailer.github_app_installation_access_token_leaked(target, user, token.token_source, url, token_type: token.type, app_name: app_name).deliver_later
              end
            end
          end
        end
      end

      def repo_is_associated_with_github_or_microsoft(repo)
        return false if repo.owner.nil?
        return false unless repo.owner.organization?
        org_in_revocation_scope?(repo.owner)
      end

      def get_app_name_for_access(access)
        return nil unless access.present?
        return nil unless access.application.present?
        access.application.name
      end

      def access_is_associated_with_github_or_microsoft(access)
        return false unless access.present?

        if access.user.present?
          if access.application.present? && access.application_type == "Integration"
            # In case access has application and the application type is "github app"
            # the apps are installed on the org, so we are querying which orgs have it installed
            return access.application.installations.where(target_id: revocation_orgs_ids, target_type: Organization.base_class).exists?
          else
            # Otherwise the access is either PAT or OAuthApplication type
            # these are authorized per-user in credential_authorizations
            access.credential_authorizations.map(&:organization).each do |org|
              return true if org_in_revocation_scope?(org)
            end
          end
        end

        false
      end

      def org_in_revocation_scope?(org)
        (org.business.present? && org.business.slug.in?(BUSINESSES_TO_REVOKE_KEYS_FROM)) || org.display_login.in?(ORGS_TO_REVOKE_KEYS_FROM)
      end

      def target_in_revocation_scope?(target:, is_one_click_revoke:, oauth_access: nil)
        return true unless target.present?
        return true unless target.private?
        return true if target.is_a?(Gist) && target.private?

        # This means the user is explicitly trying to revoke a token in a private repo
        return true if is_one_click_revoke

        # If it's associated with GitHub or Microsoft, force revocation
        if oauth_access.present?
          return true if (
            access_is_associated_with_github_or_microsoft(oauth_access) &&
            repo_is_associated_with_github_or_microsoft(target)
          )
        else
          return true if repo_is_associated_with_github_or_microsoft(target)
        end

        false
      end

      def revocation_orgs_ids
        return @revocation_orgs_ids if defined?(@revocation_orgs_ids)
        # OR the results in ruby as two queries are much faster than one here
        @revocation_orgs_ids = Organization.joins(:business).where(business: { slug: BUSINESSES_TO_REVOKE_KEYS_FROM }).pluck(:id)
        @revocation_orgs_ids |= Organization.where(login: ORGS_TO_REVOKE_KEYS_FROM).pluck(:id)
        @revocation_orgs_ids
      end

      def select_and_group_github_tokens(tokens)
        tokens
          .select { |token| GITHUB_ACCESS_TOKEN_TYPES_REVOKABLE.include?(token.type) }
          .group_by { |token| select_github_token_access_type(token.type) }
      end

      def select_github_token_access_type(type)
        case type
        when "GITHUB", "GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_OAUTH_ACCESS_TOKEN", "GITHUB_USER_TO_SERVER_TOKEN"
          oauth_access_type
        when "GITHUB_REFRESH_TOKEN"
          refresh_token_type
        when "GITHUB_SERVER_TO_SERVER_TOKEN", "GITHUB_APP_TOKEN"
          authentication_token_type
        end
      end

      def get_token_state_from_access(accesses, type, token)
        access = accesses[token]
        if access.nil?
          if type == "GITHUB"
            return :unknown
          else
            return :unverifiable
          end
        end

        # `OauthAccess` and `RefreshToken` will respond to `expired?
        if access.respond_to?(:expired?) && access.expired?
          return :revoked
        end

        # `AuthenticationToken` responds to `expires_at_timestamp`
        if type == "GITHUB_SERVER_TO_SERVER_TOKEN" || type == "GITHUB_APP_TOKEN"
          if access.expires_at_timestamp.to_i < Time.now.to_i
            return :revoked
          end
        end

        :active
      end

      def oauth_access_type
        :oauth_access
      end

      def refresh_token_type
        :refresh_token
      end

      def authentication_token_type
        :authentication_token
      end

      # returns a hash of {"type" => {token => access}} for github tokens in the incoming list
      # types are "oauth_access", "refresh_token", "authentication_token"
      def get_github_accesses(tokens)
        github_tokens = select_and_group_github_tokens(tokens)
        oauth_accesses = nil
        refresh_tokens = nil
        authentication_tokens = nil

        if github_tokens[oauth_access_type]&.any?
          oauth_accesses = for_oauth_tokens(github_tokens[oauth_access_type].map(&:token))
        end

        if github_tokens[refresh_token_type]&.any?
          refresh_tokens = for_refresh_tokens(github_tokens[refresh_token_type].map(&:token))
        end

        if github_tokens[authentication_token_type]&.any?
          authentication_tokens = for_authentication_tokens(github_tokens[authentication_token_type].map(&:token))
        end

        {
          oauth_access_type => oauth_accesses,
          refresh_token_type => refresh_tokens,
          authentication_token_type => authentication_tokens,
        }
      end

      def for_oauth_tokens(tokens)
        hashed_tokens = tokens.each_with_object({}) do |token, hash|
          hash[token] = OauthAccessTokens::Domain.hash_token(token)
        end

        accesses = T.let({}, T::Hash[T.untyped, T.untyped])

        hashed_tokens.values.each_slice(TOKEN_BATCH_SIZE) do |slice|
          slice_accesses = OauthAccessTokens.domain.by_hashed_tokens_indexed(slice)
          accesses = accesses.merge(slice_accesses)
        end

        tokens.each_with_object({}) do |token, hash|
          hash[token] = accesses[hashed_tokens[token]]
        end
      end

      def for_refresh_tokens(tokens)
        hashed_tokens = tokens.each_with_object({}) do |token, hash|
          hash[token] = RefreshToken.hash_token(token)
        end

        accesses = T.let({}, T::Hash[T.untyped, T.untyped])

        hashed_tokens.values.each_slice(TOKEN_BATCH_SIZE) do |slice|
          slice_accesses = T.must(RefreshToken.where(hashed_token: slice)
            .in_batches(of: TOKEN_BATCH_SIZE))
            .each_record
            .index_by(&:hashed_token)

          accesses = accesses.merge(slice_accesses)
        end

        tokens.each_with_object({}) do |token, hash|
          hash[token] = accesses[hashed_tokens[token]]
        end
      end

      def for_authentication_tokens(tokens)
        accesses = {}
        hashed_tokens = tokens.each_with_object({}) do |token, hash|
          hash[token] = ServerToServerTokens::Domain.hash_token(token)
        end

        accesses = ServerToServerTokens.domain.by_hashed_values(hashed_tokens.values, TOKEN_BATCH_SIZE)
        tokens.each_with_object({}) do |token, hash|
          hash[token] = accesses[hashed_tokens[token]]
        end
      end
    end
  end
end
