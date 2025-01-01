# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class KeyLinks < GH::Domain::Base
      decorate_with GH::Decorator::TestBedMemoization, only: [:cache_key, :list_for_repo]

      # Get a single autolink by ID
      sig { params(id: Integer, repo_id: Integer).returns(T.nilable(Repositories::IKeyLink)).checked(:always).on_failure(:raise) }
      def by_id(id, repo_id:)
        ::KeyLink.find_by(id: id, owner_id: repo_id)
      end

      # List all the keylinks for the given repository id
      sig { params(repo_id: Integer).returns(GH::Domain::Collection[IKeyLink]).checked(:always).on_failure(:raise) }
      def list_for_repo(repo_id)
        # TODO: this copies the previous domain interface which returned an unbounded collection of keylinks.
        # Do we want to impose a limit per repository that is checked on create?
        autolinks = ::KeyLink.where(owner_id: repo_id, owner_type: "Repository").order(id: :asc).to_a
        GH::Domain::Collection.new(autolinks)
      end

      # rubocop:disable Metrics/MethodLength
      # Create an autolink and return GH::Result::Ok if successful or GH::Result::Error::Validation if not.
      sig { params(attributes: CreateKeyLinkAttributes, repo_id: Integer).returns(T.any(GH::Result::Ok[IKeyLink], GH::Result::Error::Validation[IKeyLink])).checked(:always).on_failure(:raise) }
      def create(attributes, repo_id:)
        keylink = ::KeyLink.create(attributes.to_hash.merge(owner_id: repo_id, owner_type: "Repository"))
        if keylink.persisted?
          clear_cache
          GH::Result::Ok.new(keylink)
        else
          GH::Result::Error::Validation.new(keylink)
        end
      rescue ActiveRecord::RecordNotUnique
        keylink = T.must(keylink)
        keylink.errors.add(:key_prefix, "is already in use")
        GH::Result::Error::Validation.new(keylink)
      end
      # rubocop:enable Metrics/MethodLength

      # Deletes the identified autolink and returns GH::Result::Ok if successful or
      # GH::Result::Error::NotFound if not found.
      sig { params(id: Integer, repo_id: Integer).returns(T.any(GH::Result::Ok[IKeyLink], GH::Result::Error::NotFound[IKeyLink])).checked(:always).on_failure(:raise) }
      def destroy(id, repo_id:)
        keylink = ::KeyLink.find_by(id: id, owner_id: repo_id)
        return GH::Result::Error::NotFound.new unless keylink

        keylink.destroy
        clear_cache
        GH::Result::Ok.new(nil)
      end

      # build an autolink and return GH::Result::Ok if successful or GH::Result::Error::Validation if not.
      sig { params(attributes: CreateKeyLinkAttributes, repo_id: Integer).returns(T.any(GH::Result::Ok[IKeyLink], GH::Result::Error::Validation[IKeyLink])).checked(:always).on_failure(:raise) }
      def build(attributes, repo_id:)
        keylink = ::KeyLink.build(attributes.to_hash.merge(owner_id: repo_id, owner_type: "Repository"))
        if keylink.valid?
          GH::Result::Ok.new(keylink)
        else
          GH::Result::Error::Validation.new(keylink)
        end
      rescue ActiveRecord::RecordNotUnique
        keylink = T.must(keylink)
        keylink.errors.add(:key_prefix, "is already in use")
        GH::Result::Error::Validation.new(keylink)
      end

      # Returns the cache key for a key_link owned by a repository.
      sig { params(repo_id: Integer).returns(T.nilable(String)) }
      def cache_key(repo_id)
        ids = owner_scope(repo_id).pluck(:id)
        return nil if ids.empty?

        "kl-" + Digest::SHA256.hexdigest(ids.join(","))
      end

      # Wether or not the custom key links feature is active for the given repository.
      sig { params(repo_id: Integer).returns(T::Boolean) }
      def custom_key_links_active?(repo_id)
        cache_key(repo_id).present?
      end

      private

      sig { params(owner_id: Integer).returns(ActiveRecord::Relation) }
      def owner_scope(owner_id)
        KeyLink.where(owner_id: owner_id, owner_type: "Repository")
      end

      sig { void }
      def clear_cache
        cache.clear(method_name: :cache_key)
        cache.clear(method_name: :list_for_repo)
      end
    end
  end
end
