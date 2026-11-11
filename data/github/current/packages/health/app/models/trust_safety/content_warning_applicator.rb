# typed: strict
# frozen_string_literal: true

# Composite class which seeks to answer this question: given a repo and a user pair, plus KV-stored
# opt-in/dismiss state, should we surface a content warning?
module TrustSafety
  class ContentWarningApplicator
    # Public: Initialize with a repository and a user.
    sig { params(repository: Repository, user: User).void }
    def initialize(repository, user)
      @repository = repository
      @user = user
    end

    # Public: If the repository has a content warning, and the user has not opted in/dismissed it, return the content warning.
    # Otherwise, return nil. Note: will return in Promise form, so the caller can decide whether to await it or not.
    sig { returns(T.any(Promise[T.nilable(ActiveSupport::OrderedOptions)], Promise[NilClass])) }
    def async_content_warning
      # Respect global env-level content warnings config.
      return Promise.resolve(nil) unless GitHub.opt_in_to_restricted_repo_enabled?

      # Always skip for private repos
      return Promise.resolve(nil) if repository.private?

      repository.async_content_warning.then do |content_warning|
        # We have no network_privilege or we have no content warning for this repo.
        next Promise.resolve(nil) unless content_warning

        Promise.all([
          repository.async_writable_by?(user),
          repository.async_owner,
          repository.async_contributor?(user),
        ]).then do |writable_by, owner, is_contributor|
          # We do _not_ show warnings for users who have write-access to a repo.
          #
          # Special note: writable_by? is more expensive than #network_privilege, so guard on this only
          # after we know this repo has a network_privilege.
          next Promise.resolve(nil) if writable_by

          # Same with contributors: suppress content warnings for contributors.
          next Promise.resolve(nil) if is_contributor

          # Check if user has opted in / dismissed the warning.
          # Note: we store this value in two different places so we must honor the type of the content warning.
          dismiss = if content_warning.type == "interstitial"
            interstitial_content_warning_opted_in?
          else
            dismissed_content_warning_banner?
          end
          next Promise.resolve(nil) if dismiss

          # One more check: if the user is a member of the owning org then
          # suppress the content warning.
          if owner.is_a?(::Organization)
            owner.async_member?(user).then do |is_member|
              next Promise.resolve(nil) if is_member

              content_warning
            end
          else
            content_warning
          end
        end
      end
    end

    # Public: Has the user dismissed the content warning banner for this repository?
    sig { returns(T::Boolean) }
    def dismissed_content_warning_banner?
      # fallbacks to true if DB cluster is unavailable and does not render the content warning banner
      raw_value = Repositories::Kv.store.get(dismiss_content_warning_banner_kv_key).value { true }

      # Check via presence of the value
      raw_value.present?
    end

    # Public: Has the user opted in to repo so they will not see the interstitial content warning?
    sig { returns(T::Boolean) }
    def interstitial_content_warning_opted_in?
      raw_value = Repositories::Kv.store.get(interstitial_content_warning_opt_in_key).value { false }

      # Check via presence of the value
      raw_value.present?
    end

    # Public: Dismiss the content warning banner for this repository for the user.
    # This will persist in KV for 30 days.
    sig { void }
    def dismiss_content_warning_banner!
      Repositories::Kv.store.set(dismiss_content_warning_banner_kv_key, "1", expires: 30.days.from_now)
    end

    # Public: Opt-in to the repo and dismiss the interstitial content warning for this repository for the user.
    # This will persist in KV for 30 days.
    sig { void }
    def interstitial_content_warning_opt_in!
      Repositories::Kv.store.set(interstitial_content_warning_opt_in_key, "1", expires: 30.days.from_now)
    end

    private

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(User) }
    attr_reader :user

    sig { returns(String) }
    def interstitial_content_warning_opt_in_key
      "opt_in_to_flagged_repo.#{user.id}.#{repository.id}"
    end

    sig { returns(String) }
    def dismiss_content_warning_banner_kv_key
      "dismissed_content_warning_from_flagged_repo.#{user.id}.#{repository.id}"
    end
  end
end
