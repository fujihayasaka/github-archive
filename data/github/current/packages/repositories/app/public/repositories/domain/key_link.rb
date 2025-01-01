# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class KeyLink < GH::Domain::Base
      extend T::Sig

      decorate_with GH::Decorator::Frozen

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

      # Create an autolink and return GH::Result::Ok if successful or GH::Result::Error::Validation if not.
      sig { params(attributes: CreateKeyLinkAttributes, repo_id: Integer).returns(GH::Result[IKeyLink]).checked(:always).on_failure(:raise) }
      def create(attributes, repo_id:)
        keylink = ::KeyLink.create(attributes.to_hash.merge(owner_id: repo_id, owner_type: "Repository"))
        if keylink.persisted?
          GH::Result::Ok.new(keylink)
        else
          GH::Result::Error::Validation.new(keylink)
        end
      rescue ActiveRecord::RecordNotUnique
        keylink = T.must(keylink)
        keylink.errors.add(:key_prefix, "is already in use")
        GH::Result::Error::Validation.new(keylink)
      end

      # Deletes the identified autolink and returns GH::Result::Ok if successful or
      # GH::Result::Error::NotFound if not found.
      sig { params(id: Integer, repo_id: Integer).returns(GH::Result[NilClass]).checked(:always).on_failure(:raise) }
      def destroy(id, repo_id:)
        keylink = ::KeyLink.find_by(id: id, owner_id: repo_id)
        return GH::Result::Error::NotFound.new unless keylink

        keylink.destroy
        GH::Result::Ok.new(nil)
      end
    end
  end
end
